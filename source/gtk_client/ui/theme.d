module gtk_client.ui.theme;

import gtk.widget;
import gtk.application_window;
import gtk.settings;
import gtk.types;
import gtk.css_provider;
import gtk.style_context;
import gdk.display;

import std.string;
import std.file;
import std.conv;

import logging;

class ThemeManager
{
    private CssProvider cssProvider;
    private bool isDarkTheme;

    this()
    {
        cssProvider = new CssProvider();
    }

    void setTheme(ApplicationWindow window, bool darkMode)
    {
        isDarkTheme = darkMode;

        auto settings = gtk.settings.Settings.getDefault();
        if (settings)
        {
            settings.gtkApplicationPreferDarkTheme = darkMode;
        }

        string cssFile = darkMode ? "resources/css/dark.css" : "resources/css/light.css";

        try
        {
            if (exists(cssFile))
            {
                cssProvider.loadFromPath(cssFile);

                auto display = Display.getDefault();
                StyleContext.addProviderForDisplay(display, cssProvider, STYLE_PROVIDER_PRIORITY_APPLICATION);
            }
        }
        catch (Exception e)
        {
            logToTerminal("Failed to load CSS: " ~ e.toString(), "ERROR", "ThemeManager");
        }
    }

    void applyTheme(ApplicationWindow window, bool darkMode)
    {
        setTheme(window, darkMode);
    }

    bool isDark() const
    {
        return isDarkTheme;
    }
}
