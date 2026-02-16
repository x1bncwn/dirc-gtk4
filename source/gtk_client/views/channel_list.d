module gtk_client.views.channel_list;

import gtk.tree_view;
import gtk.tree_store;
import gtk.tree_iter;
import gtk.tree_selection;
import gtk.tree_view_column;
import gtk.cell_renderer_text;
import gtk.scrolled_window;
import gtk.box;
import gtk.types;
import gtk.label;
import gtk.separator;
import gtk.tree_model;

import gobject.value;
import gobject.types;

import std.string;
import std.conv;
import std.algorithm;

import logging;
import gtk_client.ui.builder;

class ChannelListView
{
    private TreeView treeView;
    private TreeStore store;
    private ScrolledWindow scrolledWindow;
    private Box sidebar;

    // Callback for selection changes
    private void delegate(string display, string server, string type) selectionCallback;

    void initialize(UIBuilder uiBuilder)
    {
        treeView = uiBuilder.getTreeView("channel_tree");
        scrolledWindow = uiBuilder.getScrolledWindow("sidebar_scrolled");
        sidebar = uiBuilder.getBox("sidebar_box");

        // Initialize store
        store = TreeStore.new_([GTypeEnum.String, GTypeEnum.String]);
        treeView.setModel(store);

        // Configure tree view
        //auto renderer = new CellRendererText();
        //auto column = new TreeViewColumn();
        //column.setTitle("Name");
        //column.packStart(renderer, true);
        //column.addAttribute(renderer, "text", 0);
        //treeView.appendColumn(column);

        treeView.setHeadersVisible(false);
        treeView.setVexpand(true);
        treeView.setHexpand(true);

        // Connect selection signal
        auto selection = treeView.getSelection();
        selection.connectChanged(delegate {
            TreeModel model;
            TreeIter iter;
            if (selection.getSelected(model, iter))
            {
                Value nameVal = new Value("");
                store.getValue(iter, 0, nameVal);
                string display = nameVal.getString();

                Value typeVal = new Value("");
                store.getValue(iter, 1, typeVal);
                string itemType = typeVal.getString();

                string server = "";
                if (itemType == "channel")
                {
                    TreeIter parentIter;
                    if (store.iterParent(parentIter, iter))
                    {
                        Value parentVal = new Value("");
                        store.getValue(parentIter, 0, parentVal);
                        server = parentVal.getString();
                    }
                }
                else if (itemType == "server")
                {
                    server = display;
                }

                logToTerminal("Selected: " ~ display ~ " (type: " ~ itemType ~ ")", "INFO", "ChannelList");

                if (selectionCallback !is null)
                    selectionCallback(display, server, itemType);
            }
        });
    }

    void setSelectionCallback(void delegate(string, string, string) cb)
    {
        selectionCallback = cb;
    }

    void addServer(string server)
    {
        logToTerminal("addServer ENTERED: " ~ server, "DEBUG", "channel");
        logToTerminal("store is null? " ~ to!string(store is null), "DEBUG", "channel");

        TreeIter serverIter;
        if (!findServer(server, serverIter))
        {
            TreeIter newIter;
            store.append(newIter, null);
            store.setValue(newIter, 0, new Value(server));
            store.setValue(newIter, 1, new Value("server"));
        }
    }

    void addChannel(string server, string channel)
    {
        TreeIter serverIter;
        if (findServer(server, serverIter))
        {
            TreeIter channelIter;
            if (!findChannel(serverIter, channel, channelIter))
            {
                TreeIter newIter;
                store.append(newIter, serverIter);
                store.setValue(newIter, 0, new Value(channel));
                store.setValue(newIter, 1, new Value("channel"));
                treeView.expandRow(store.getPath(serverIter), false);
            }
        }
    }

    void removeChannel(string server, string channel)
    {
        TreeIter serverIter;
        if (findServer(server, serverIter))
        {
            TreeIter channelIter;
            if (findChannel(serverIter, channel, channelIter))
            {
                store.remove(channelIter);
            }
        }
    }

    void removeServer(string server)
    {
        TreeIter serverIter;
        if (findServer(server, serverIter))
        {
            store.remove(serverIter);
        }
    }

    void clear()
    {
        store.clear();
    }

    string getLastDisplay()
    {
        TreeIter iter;
        if (store.getIterFirst(iter))
        {
            // Find the last item in tree
            TreeIter lastIter = iter;
            while (store.iterNext(lastIter)) {}

            Value val = new Value("");
            store.getValue(lastIter, 0, val);
            return val.getString();
        }
        return "System";
    }

    string getServerForDisplay(string display)
    {
        TreeIter iter;
        if (findDisplay(display, iter))
        {
            Value typeVal = new Value("");
            store.getValue(iter, 1, typeVal);
            string itemType = typeVal.getString();

            if (itemType == "server")
                return display;
            else if (itemType == "channel")
            {
                TreeIter parentIter;
                if (store.iterParent(parentIter, iter))
                {
                    Value parentVal = new Value("");
                    store.getValue(parentIter, 0, parentVal);
                    return parentVal.getString();
                }
            }
        }
        return "";
    }

    private bool findServer(string server, ref TreeIter iter)
    {
        TreeIter childIter;
        if (store.getIterFirst(childIter))
        {
            do
            {
                Value nameVal = new Value("");
                store.getValue(childIter, 0, nameVal);
                string name = nameVal.getString();

                Value typeVal = new Value("");
                store.getValue(childIter, 1, typeVal);
                string type = typeVal.getString();

                if (type == "server" && name == server)
                {
                    iter = childIter;
                    return true;
                }
            }
            while (store.iterNext(childIter));
        }
        return false;
    }

    private bool findChannel(TreeIter serverIter, string channel, ref TreeIter iter)
    {
        TreeIter childIter;
        if (store.iterChildren(childIter, serverIter))
        {
            do
            {
                Value nameVal = new Value("");
                store.getValue(childIter, 0, nameVal);
                string name = nameVal.getString();

                if (name == channel)
                {
                    iter = childIter;
                    return true;
                }
            }
            while (store.iterNext(childIter));
        }
        return false;
    }

    private bool findDisplay(string display, ref TreeIter iter)
    {
        TreeIter childIter;
        if (store.getIterFirst(childIter))
        {
            do
            {
                Value nameVal = new Value("");
                store.getValue(childIter, 0, nameVal);
                string name = nameVal.getString();

                if (name == display)
                {
                    iter = childIter;
                    return true;
                }

                // Check children
                TreeIter subIter;
                if (store.iterChildren(subIter, childIter))
                {
                    do
                    {
                        Value subNameVal = new Value("");
                        store.getValue(subIter, 0, subNameVal);
                        string subName = subNameVal.getString();

                        if (subName == display)
                        {
                            iter = subIter;
                            return true;
                        }
                    }
                    while (store.iterNext(subIter));
                }
            }
            while (store.iterNext(childIter));
        }
        return false;
    }
}
