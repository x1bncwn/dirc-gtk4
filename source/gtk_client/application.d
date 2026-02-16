module gtk_client.application;

import gtk.application;
import gtk.application_window;
import gtk.box;
import gtk.paned;
import gtk.header_bar;
import gtk.menu_button;
import gtk.popover_menu;
import gtk.window;
import gtk.settings;

import gio.menu;
import gio.menu_model;
import gio.types;
import gio.simple_action;

import gobject.types;

import std.concurrency;
import std.string;
import std.conv;
import std.algorithm;
import std.datetime;
import std.range;

import core.thread;

import models;
import logging;
import irc_client;

import gtk_client.ui.builder;
import gtk_client.ui.theme;
import gtk_client.views.chat_view;
import gtk_client.views.channel_list;
import gtk_client.views.input_handler;

struct ServerConnection
{
    Tid threadId;
    bool connected;
    string serverName;
}

class GTKClient
{
    // Core GTK objects
    private Application app;
    private ApplicationWindow window;
    private UIBuilder uiBuilder;
    private ThemeManager themeManager;

    // Views
    private ChatView chatView;
    private ChannelListView channelList;
    private InputHandler inputHandler;

    // Pipe communication
    private int[2] pipeFds;
    private uint pipeSourceId = 0;

    // State
    private string currentDisplay;
    private string currentServer;
    private ServerConnection[string] connections;
    private Tid[string] serverThreads;

    // Data
    private string[string][string] channelTopics;

    this()
    {
		import core.stdc.errno : errno;
		import core.sys.posix.fcntl : fcntl, F_GETFL, F_SETFL, O_NONBLOCK;
		import core.sys.posix.unistd : pipe;

        logToTerminal("Initializing GTK application", "INFO", "main");
        app = new Application("org.example.dIRC", ApplicationFlags.FlagsNone);

        // Create pipe for io callback
        logToTerminal("Creating pipe...", "DEBUG", "main");
        if (pipe(pipeFds) == -1)
        {
            logToTerminal("Failed to create pipe, errno: " ~ to!string(errno), "ERROR", "main");
            throw new Exception("Failed to create pipe: " ~ to!string(errno));
        }
        logToTerminal("Pipe created: read fd=" ~ to!string(pipeFds[0]) ~ ", write fd=" ~ to!string(pipeFds[1]), "DEBUG", "main");

        // Set non-blocking
        foreach (i, fd; pipeFds)
        {
            auto flags = fcntl(fd, F_GETFL, 0);
            if (fcntl(fd, F_SETFL, flags | O_NONBLOCK) == -1)
            {
                logToTerminal("Failed to set non-blocking on fd " ~ to!string(fd) ~ ", errno: " ~ to!string(errno), "WARNING", "main");
            }
        }

        chatView = new ChatView();
        channelList = new ChannelListView();
        inputHandler = new InputHandler(chatView, channelList);

        app.connectActivate(delegate(Application app) { setupGui(); });
    }

    ~this()
    {
        import core.sys.posix.unistd : close;
		import glib.source : Source;

        // Clean up pipe
        if (pipeSourceId > 0)
        {
            Source.remove(pipeSourceId);
        }
        if (pipeFds[0] != 0)
            close(pipeFds[0]);
        if (pipeFds[1] != 0)
            close(pipeFds[1]);
    }

    private void processPendingMessages()
    {
		import core.atomic : atomicExchange;
        do
        {
            bool gotMessage = true;
            while (gotMessage)
            {
                gotMessage = receiveTimeout(Duration.zero, (IrcToGtkMessage msg) {
                    logToTerminal("Processing message of type: " ~ to!string(msg.type), "DEBUG", "main");

                    final switch (msg.type)
                    {
                        case IrcToGtkType.chatMessage:
                            auto data = msg.chat;
                            string display = data.channel.length > 0 ? data.channel : data.server;
                            chatView.appendMessage(display, data.timestamp,
                                data.prefix ~ data.rawNick, data.messageType, data.body);
                            break;
                        case IrcToGtkType.channelUpdate:
                            auto u = msg.channelUpdate;
                            handleChannelUpdate(u.server, u.channel, u.action);
                            break;
                        case IrcToGtkType.systemMessage:
                            auto sysMsg = msg.systemMsg;
                            string target = currentServer.length > 0 ? currentServer : "System";
                            chatView.appendSystemMessage(target, sysMsg.text);
                            break;
                        case IrcToGtkType.channelTopic:
                            auto topicData = msg.topicData;
                            handleChannelTopic(topicData.server, topicData.channel, topicData.topic);
                            break;
                    }
                    return true;
                });
            }
        } while (atomicExchange(&pipeSignalPending, false));
    }

    private void setupGui()
    {
        logToTerminal("Setting up GUI", "INFO", "main");

        // Initialize UI Builder
        uiBuilder = new UIBuilder();
        uiBuilder.loadUI("resources/gtk/main_window.ui");

        // Setup window
        window = uiBuilder.getWindow("main_window");
        window.setApplication(app);

        // Initialize theme manager
        themeManager = new ThemeManager();
        themeManager.applyTheme(window, true);

        // Get UI elements from builder
        auto headerBar = uiBuilder.getHeaderBar("header_bar");

        // Setup menu
        setupMenu(headerBar);

        // Initialize views with UI elements
        chatView.initialize(uiBuilder);
        channelList.initialize(uiBuilder);
        inputHandler.initialize(uiBuilder, delegate() { sendMessage(); });

        // Connect view signals
        channelList.setSelectionCallback((string display, string server, string type) {
            currentDisplay = display;
            currentServer = server;
            chatView.switchToDisplay(display);
        });

        // Setup actions
        setupActions();

        // Setup pipe watch
        setupPipeWatch();

        window.present();

        // Show welcome message
        showWelcomeMessage();
    }

    private void setupPipeWatch()
    {
		import core.stdc.errno : errno, EAGAIN, EWOULDBLOCK;
		import core.sys.posix.unistd : read, ssize_t;
		import glib.iochannel : IOChannel;
		import glib.types : IOCondition;
		import glib.global : ioAddWatch;

        logToTerminal("Setting up pipe watch on fd " ~ to!string(pipeFds[0]), "DEBUG", "main");
        auto channel = IOChannel.unixNew(pipeFds[0]);
        if (channel is null)
        {
            logToTerminal("IOChannel.unixNew returned null", "ERROR", "main");
            throw new Exception("Failed to create IOChannel for pipe");
        }
        logToTerminal("Created IOChannel successfully", "DEBUG", "main");

        pipeSourceId = ioAddWatch(channel, 0, IOCondition.In | IOCondition.Hup | IOCondition.Err, delegate bool(IOChannel channel, IOCondition condition) {
            logToTerminal("Pipe callback fired, condition: " ~ to!string(condition), "DEBUG", "main");

            if (condition & IOCondition.In)
            {
                // Drain pipe
                char[1] buffer;
                ssize_t bytesRead = 0;
                do
                {
                    bytesRead = read(pipeFds[0], buffer.ptr, 1);
                    if (bytesRead > 0)
                    {
                        logToTerminal("Read " ~ to!string(bytesRead) ~ " bytes from pipe", "DEBUG", "main");
                    }
                    else if (bytesRead == -1 && errno != EAGAIN && errno != EWOULDBLOCK)
                    {
                        logToTerminal("Read error, errno: " ~ to!string(errno), "ERROR", "main");
                    }
                }
                while (bytesRead > 0);

                // Process messages
                processPendingMessages();
            }

            if (condition & (IOCondition.Hup | IOCondition.Err))
            {
                logToTerminal("Pipe HUP or ERR condition", "ERROR", "main");
                return false;
            }

            return true;
        });

        logToTerminal("ioAddWatch returned source ID: " ~ to!string(pipeSourceId), "DEBUG", "main");
		
		window.connectCloseRequest(delegate(Window window) {
            logToTerminal("Close request received", "INFO", "main");
            disconnectAllServers();

            // Remove pipe source
            if (pipeSourceId > 0)
            {
                Source.remove(pipeSourceId);
            }

            // Close IRC threads
            foreach (server, tid; serverThreads)
            {
                send(tid, IrcFromGtkMessage(IrcFromGtkMessage.Type.UpdateChannels, "", "", "quit"));
            }

            Thread.sleep(100.msecs);
            app.quit();
            return true;
        });
    }

    private void setupMenu(HeaderBar headerBar)
    {
        auto menuButton = new MenuButton();
        menuButton.setIconName("open-menu-symbolic");
        headerBar.packStart(menuButton);

        auto menu = new Menu();
        menu.append("Connect", "app.connect");
        menu.append("Disconnect", "app.disconnect");
        menu.append("Quit", "app.quit");
        menu.append("Light Theme", "app.light-theme");
        menu.append("Dark Theme", "app.dark-theme");

        auto popoverMenu = PopoverMenu.newFromModel(menu);
        menuButton.setPopover(popoverMenu);
    }

    private void setupActions()
    {
		import glib.variant : Variant;

        auto connectAction = new SimpleAction("connect", null);
        connectAction.connectActivate(delegate(Variant parameter) {
            logToTerminal("Connect action triggered", "INFO", "main");
            startConnection(defaultServer);
        });
        app.addAction(connectAction);

        auto disconnectAction = new SimpleAction("disconnect", null);
        disconnectAction.connectActivate(delegate(Variant parameter) {
            logToTerminal("Disconnect action triggered", "INFO", "main");
            disconnectFromServer();
        });
        app.addAction(disconnectAction);

        auto quitAction = new SimpleAction("quit", null);
        quitAction.connectActivate(delegate(Variant parameter) {
            logToTerminal("Quit action triggered", "INFO", "main");
            disconnectAllServers();
            app.quit();
        });
        app.addAction(quitAction);

        auto lightThemeAction = new SimpleAction("light-theme", null);
        lightThemeAction.connectActivate(delegate(Variant parameter) {
            logToTerminal("Switching to light theme", "INFO", "main");
            themeManager.setTheme(window, false);
            chatView.updateTheme(false);
        });
        app.addAction(lightThemeAction);

        auto darkThemeAction = new SimpleAction("dark-theme", null);
        darkThemeAction.connectActivate(delegate(Variant parameter) {
            logToTerminal("Switching to dark theme", "INFO", "main");
            themeManager.setTheme(window, true);
            chatView.updateTheme(true);
        });
        app.addAction(darkThemeAction);
    }

    private void handleChannelUpdate(string server, string channel, string action)
    {
        logToTerminal("Updating channel list: " ~ server ~ " -> " ~ channel ~ " " ~ action, "INFO", "main");

        if (action == "join")
        {
            channelList.addChannel(server, channel);
            chatView.createBuffer(channel);

            if (inputHandler.autoSwitchToNewChannels)
            {
                currentDisplay = channel;
                currentServer = server;
                chatView.switchToDisplay(channel);
            }

            if (server in channelTopics && channel in channelTopics[server])
            {
                string topic = channelTopics[server][channel];
                chatView.appendSystemMessage(channel, "Topic: " ~ topic);
            }
        }
        else if (action == "part")
        {
            channelList.removeChannel(server, channel);

            if (currentDisplay == channel)
            {
                auto newDisplay = channelList.getLastDisplay();
                currentDisplay = newDisplay;
                currentServer = channelList.getServerForDisplay(newDisplay);
                chatView.switchToDisplay(currentDisplay);
            }

            if (server in channelTopics)
            {
                channelTopics[server].remove(channel);
            }
        }
    }

    private void handleChannelTopic(string server, string channel, string topic)
    {
        if (!(server in channelTopics))
            channelTopics[server] = null;

        channelTopics[server][channel] = topic;

        string target = channel in chatView.getBuffers() ? channel : server;
        chatView.appendSystemMessage(target, "Topic: " ~ topic);
    }

    private void startConnection(string server)
    {
        logToTerminal("startConnection called with server: " ~ server, "DEBUG", "main");
        logToTerminal("connections length: " ~ to!string(connections.length), "DEBUG", "main");
        logToTerminal("serverThreads length: " ~ to!string(serverThreads.length), "DEBUG", "main");

        if (server in connections && connections[server].connected)
        {
            chatView.appendSystemMessage("System", "Already connected to " ~ server ~ ".");
            return;
        }

        logToTerminal("Starting connection to " ~ server, "INFO", "main");
        logToTerminal("pipeFds[1] = " ~ to!string(pipeFds[1]), "DEBUG", "main");

        auto tid = spawn(&runIrcServer, server.strip(), thisTid, pipeFds[1]);
        logToTerminal("spawn returned tid: " ~ to!string(tid), "DEBUG", "main");

        serverThreads[server] = tid;
        connections[server] = ServerConnection(tid, true, server);

        logToTerminal("Creating buffer for server: " ~ server, "DEBUG", "main");
        chatView.createBuffer(server);

        logToTerminal("Adding server to tree: " ~ server, "DEBUG", "main");
        channelList.addServer(server);

        currentDisplay = server;
        currentServer = server;

        logToTerminal("Switching to display: " ~ server, "DEBUG", "main");
        chatView.switchToDisplay(server);

        logToTerminal("Appending connecting message", "DEBUG", "main");
        chatView.appendSystemMessage(server, "Connecting to " ~ server ~ "...");
    }

    private void disconnectFromServer()
    {
        if (currentServer.length == 0 || !(currentServer in serverThreads))
            return;

        auto tid = serverThreads[currentServer];
        send(tid, IrcFromGtkMessage(IrcFromGtkMessage.Type.UpdateChannels, "", "", "quit"));
        Thread.sleep(100.msecs);

        channelList.removeServer(currentServer);
        connections.remove(currentServer);
        serverThreads.remove(currentServer);

        chatView.appendSystemMessage("System", "Disconnected from " ~ currentServer ~ ".");

        currentServer = "";
        currentDisplay = "System";
        chatView.switchToDisplay("System");
    }

    private void disconnectAllServers()
    {
        foreach (server, tid; serverThreads)
        {
            send(tid, IrcFromGtkMessage(IrcFromGtkMessage.Type.UpdateChannels, "", "", "quit"));
        }

        Thread.sleep(150.msecs);
        channelList.clear();
        connections = null;
        serverThreads = null;

        chatView.appendSystemMessage("System", "Disconnected from all servers.");

        currentDisplay = "System";
        currentServer = "";
        chatView.switchToDisplay("System");
    }

    private void sendMessage()
    {
		auto text = inputHandler.getText();
		inputHandler.clearInput();

        if (text.length == 0)
            return;

        logToTerminal("User input: " ~ text, "INFO", "main");

        if (currentServer.length == 0 || !(currentServer in serverThreads))
        {
            chatView.appendSystemMessage("System", "Not connected to any server.");
            return;
        }

        if (text.length > 1 && text[0] == '/')
        {
            handleCommand(text);
            return;
        }

        inputHandler.handleMessage(serverThreads[currentServer], currentServer,
	    currentDisplay, text);
    }

    private void handleCommand(string text)
    {
        inputHandler.handleCommand(serverThreads[currentServer], currentServer,
            currentDisplay, text,
            delegate() { disconnectFromServer(); },
            delegate(string server) { startConnection(server); },
            delegate(string s, string c, string a) { handleChannelUpdate(s, c, a); }
        );
    }

    private void showWelcomeMessage()
    {
        chatView.appendSystemMessage("System", "Welcome to D IRC Client!");
        chatView.appendSystemMessage("System", "Type /connect <server> to connect to an IRC server");
        chatView.appendSystemMessage("System", "Type /join #channel to join a channel");
        chatView.appendSystemMessage("System", "Type /whois <nickname> for user information");
        chatView.appendSystemMessage("System", "Type /help for more commands");
    }

    void run()
    {
        app.run([]);
    }
}
