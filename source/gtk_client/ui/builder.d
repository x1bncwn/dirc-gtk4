module gtk_client.ui.builder;

import gtk.builder;
import gtk.application_window;
import gtk.scrolled_window;
import gtk.header_bar;
import gtk.text_view;
import gtk.entry;
import gtk.tree_view;
import gtk.box;
import gtk.button;
import gtk.paned;

import std.string;
import std.conv;
import std.file;

import logging;

class UIBuilder
{
    private Builder builder;

    this()
    {
        builder = new Builder();
    }

    void loadUI(string uiFilePath)
    {
        if (exists(uiFilePath))
        {
            try
            {
                builder.addFromFile(uiFilePath);
            }
            catch (Exception e)
            {
                logToTerminal("Failed to load UI file: " ~ e.toString(), "ERROR", "UIBuilder");
                createDefaultUI();
            }
        }
        else
        {
            logToTerminal("UI file not found: " ~ uiFilePath ~ ", using defaults", "WARNING", "UIBuilder");
            // createDefaultUI();
        }
    }

    private void createDefaultUI()
    {
        // Create a default UI programmatically
        // This can be expanded with a fallback UI
    }

    ApplicationWindow getWindow(string name)
    {
        return cast(ApplicationWindow)builder.getObject(name);
    }

    ScrolledWindow getScrolledWindow(string name)
    {
    	return cast(ScrolledWindow)builder.getObject(name);
    }

    HeaderBar getHeaderBar(string name)
    {
        return cast(HeaderBar)builder.getObject(name);
    }

    TextView getTextView(string name)
    {
        return cast(TextView)builder.getObject(name);
    }


    Button getButton(string name)
    {
    	return cast(Button)builder.getObject(name);
    }

    Entry getEntry(string name)
    {
        return cast(Entry)builder.getObject(name);
    }

    TreeView getTreeView(string name)
    {
        return cast(TreeView)builder.getObject(name);
    }

    Box getBox(string name)
    {
        return cast(Box)builder.getObject(name);
    }

    Paned getPaned(string name)
    {
        return cast(Paned)builder.getObject(name);
    }

    Object getObject(string name)
    {
        return builder.getObject(name);
    }
}
