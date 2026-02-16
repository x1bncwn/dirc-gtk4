module gtk_client.views.input_handler;

import gtk.entry;
import gtk.button;
import gtk.box;
import gtk.types;

import std.string;
import std.conv;
import std.algorithm;
import std.datetime;
import std.concurrency;

import logging;
import models;
import gtk_client.ui.builder;
import gtk_client.views.chat_view;
import gtk_client.views.channel_list;

class InputHandler
{
    private Entry inputEntry;
    private Button sendButton;
    private Box container;

    private ChatView chatView;
    private ChannelListView channelList;
    private void delegate() sendCallback;

    // Settings
    public bool autoSwitchToNewChannels = true;

    this(ChatView chat, ChannelListView channel)
    {
    	chatView = chat;
    	channelList = channel;
    }

    void initialize(UIBuilder uiBuilder, void delegate() sendCb)
    {
        inputEntry = uiBuilder.getEntry("input_entry");
        sendButton = uiBuilder.getButton("send_button");
        container = uiBuilder.getBox("input_box");

        sendCallback = sendCb;

        if (inputEntry is null)
        {
            // Create fallback
            container = new Box(Orientation.Horizontal, 5);
            container.setMarginStart(5);
            container.setMarginEnd(5);
            container.setMarginBottom(5);
            container.setMarginTop(5);

            inputEntry = new Entry();
            inputEntry.setHexpand(true);
            inputEntry.setPlaceholderText("Type message or command...");

            sendButton = new Button();
            sendButton.setLabel("Send");
            sendButton.setMarginStart(5);

            container.append(inputEntry);
            container.append(sendButton);
        }

        // Connect signals
        inputEntry.connectActivate(delegate(Entry entry) { 
            sendCallback();
        });

        sendButton.connectClicked(delegate(Button button) { 
            sendCallback();
        });
    }

    void handleMessage(Tid serverThread, string currentServer, 
            string currentDisplay, string text)
    {
        if (currentDisplay == currentServer)
        {
            auto spacePos = text.indexOf(" ");
            if (spacePos != -1)
            {
                auto recipient = text[0 .. spacePos].strip();
                auto message = text[spacePos .. $].strip();
                send(serverThread, IrcFromGtkMessage(IrcFromGtkMessage.Type.Message, recipient, message, ""));
            }
            else
            {
                chatView.appendSystemMessage(currentServer, "Usage: nick message (for private messages)");
            }
        }
        else if (currentDisplay.startsWith("#"))
        {
            send(serverThread, IrcFromGtkMessage(IrcFromGtkMessage.Type.Message, currentDisplay, text, ""));
        }
        else
        {
            chatView.appendSystemMessage("System", "Cannot send message to this tab.");
        }
    }

    void handleCommand(Tid serverThread, string currentServer, 
            string currentDisplay, string text,
            void delegate() disconnectCallback,
            void delegate(string) connectCallback,
            void delegate(string, string, string) channelUpdateCallback)
    {
        if (text.startsWith("/connect "))
        {
            auto server = text["/connect ".length .. $].strip();
            connectCallback(server);
        }
        else if (text.startsWith("/join "))
        {
            auto channel = text["/join ".length .. $].strip();
            if (!channel.startsWith("#"))
                channel = "#" ~ channel;

            chatView.appendSystemMessage(currentServer, "Joining " ~ channel);
            send(serverThread, IrcFromGtkMessage(IrcFromGtkMessage.Type.UpdateChannels, channel, "", "join"));
            channelUpdateCallback(currentServer, channel, "join");
        }
        else if (text.startsWith("/part "))
        {
            auto channel = text["/part ".length .. $].strip();
            chatView.appendSystemMessage(currentServer, "Leaving " ~ channel);
            send(serverThread, IrcFromGtkMessage(IrcFromGtkMessage.Type.UpdateChannels, channel, "", "part"));
            channelUpdateCallback(currentServer, channel, "part");
        }
        else if (text.startsWith("/whois "))
        {
            auto target = text["/whois ".length .. $].strip();
            if (currentServer.length > 0 && !(serverThread is Tid.init))
            {
                send(serverThread, IrcFromGtkMessage(IrcFromGtkMessage.Type.UpdateChannels, target, "", "whois"));
                chatView.appendMessage(currentDisplay, formatTimestampNow(), "", "system", "WHOIS request sent for " ~ target);
            }
            else
            {
                chatView.appendSystemMessage("System", "Not connected to a server.");
            }
        }
        else if (text.startsWith("/disconnect"))
        {
            disconnectCallback();
        }
        else if (text.startsWith("/quit"))
        {
            chatView.appendSystemMessage("System", "Goodbye!");
            // Quit handled by application
        }
        else if (text.startsWith("/msg ") || text.startsWith("/query "))
        {
            auto rest = text["/msg ".length .. $].strip();
            auto spacePos = rest.indexOf(" ");
            if (spacePos != -1)
            {
                auto recipient = rest[0 .. spacePos].strip();
                auto message = rest[spacePos .. $].strip();
                send(serverThread, IrcFromGtkMessage(IrcFromGtkMessage.Type.Message, recipient, message, ""));
            }
            else
            {
                chatView.appendSystemMessage(currentDisplay, "Usage: /msg nick message");
            }
        }
        else if (text.startsWith("/me "))
        {
            if (currentDisplay.startsWith("#"))
            {
                auto action = text["/me ".length .. $];
                string actionMsg = "\x01ACTION " ~ action ~ "\x01";
                send(serverThread, IrcFromGtkMessage(IrcFromGtkMessage.Type.Message, currentDisplay, actionMsg, ""));
            }
            else
            {
                chatView.appendSystemMessage(currentDisplay, "/me can only be used in channels");
            }
        }
        else if (text.startsWith("/nick "))
        {
            auto newNick = text["/nick ".length .. $].strip();
            send(serverThread, IrcFromGtkMessage(IrcFromGtkMessage.Type.Message, "", "NICK " ~ newNick, ""));
            chatView.appendMessage(currentServer, formatTimestampNow(), defaultNick, "system", "Changing nickname to: " ~ newNick);
        }
        else if (text.startsWith("/help"))
        {
            showHelp();
        }
        else
        {
            string rawCommand = text[1 .. $];
            send(serverThread, IrcFromGtkMessage(IrcFromGtkMessage.Type.Message, "", rawCommand, ""));

            string target = currentDisplay.startsWith("#") ? currentDisplay : currentServer;
            chatView.appendMessage(target, formatTimestampNow(), "", "system", ">>> " ~ rawCommand);
        }
    }

    private void showHelp()
    {
        chatView.appendSystemMessage("System", "Available commands:");
        chatView.appendSystemMessage("System", "  /connect <server> - Connect to an IRC server");
        chatView.appendSystemMessage("System", "  /join <#channel> - Join a channel");
        chatView.appendSystemMessage("System", "  /part [channel] - Leave current or specified channel");
        chatView.appendSystemMessage("System", "  /whois <nickname> - Get user information");
        chatView.appendSystemMessage("System", "  /msg <nick> <message> - Send private message");
        chatView.appendSystemMessage("System", "  /me <action> - Send action to channel");
        chatView.appendSystemMessage("System", "  /nick <newnick> - Change nickname");
        chatView.appendSystemMessage("System", "  /disconnect - Disconnect from current server");
        chatView.appendSystemMessage("System", "  /quit - Quit the application");
        chatView.appendSystemMessage("System", "  /help - Show this help");
    }

    private string formatTimestampNow()
    {
        import std.datetime;
        auto now = Clock.currTime();
        return "[" ~ format("%02d:%02d", now.hour, now.minute) ~ "]";
    }

    void clearInput()
    {
        if (inputEntry !is null)
            inputEntry.setText("");
    }

    string getText()
    {
	return inputEntry !is null ? inputEntry.getText() : "";
    }
}
