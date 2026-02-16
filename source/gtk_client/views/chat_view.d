module gtk_client.views.chat_view;

import gtk.text_view;
import gtk.text_buffer;
import gtk.text_iter;
import gtk.text_tag;
import gtk.text_tag_table;
import gtk.scrolled_window;
import gtk.box;
import gtk.paned;
import gtk.c.types;
import gtk.c.functions;
import gtk.types;

import std.string;
import std.conv;
import std.datetime;
import std.algorithm;

import logging;
import gtk_client.ui.builder;
import gtk_client.utils.color;

class ChatView
{
    private TextView textView;
    private TextBuffer textBuffer;
    private ScrolledWindow scrolledChat;
    private Box chatAreaBox;
    private UIBuilder uiBuilder;
    private ColorGenerator colorGen;

    private TextBuffer[string] displayBuffers;
    private string currentDisplay;

    private TextTag[string][string] nicknameTags;
    private TextTag[string][string] modeSymbolTags;
    private TextTag[string] timestampTags;
    private TextTag[string] systemMessageTags;

    private bool isDarkTheme = true;
    private bool colorizeNicks = true;

    this()
    {
        colorGen = new ColorGenerator();
        displayBuffers["System"] = new TextBuffer(null);
    }

    void initialize(UIBuilder uiBuilder)
    {
        this.uiBuilder = uiBuilder;

        chatAreaBox = uiBuilder.getBox("chat_area_box");
        scrolledChat = uiBuilder.getScrolledWindow("chat_scrolled");
        textView = uiBuilder.getTextView("chat_text_view");

        if (textView is null)
        {
            // Create fallback
            chatAreaBox = new Box(Orientation.Vertical, 5);
            chatAreaBox.setMarginStart(5);
            chatAreaBox.setMarginEnd(5);
            chatAreaBox.setMarginTop(5);
            chatAreaBox.setMarginBottom(5);
            chatAreaBox.setVexpand(true);
            chatAreaBox.setHexpand(true);

            auto chatBox = new Box(Orientation.Vertical, 0);
            chatBox.setVexpand(true);
            chatBox.setHexpand(true);

            textView = new TextView();
            textView.setEditable(false);
            textView.setWrapMode(WrapMode.Word);
            textView.setVexpand(true);
            textView.setHexpand(true);
            textView.setAcceptsTab(false);

            scrolledChat = new ScrolledWindow();
            scrolledChat.setPolicy(PolicyType.Automatic, PolicyType.Automatic);
            scrolledChat.setChild(textView);
            scrolledChat.setVexpand(true);
            scrolledChat.setHexpand(true);

            chatBox.append(scrolledChat);
            chatAreaBox.append(chatBox);
        }

        textBuffer = displayBuffers["System"];
        textView.setBuffer(textBuffer);
        initializeTextTags("System");
    }

    void setTheme(bool darkMode)
    {
        isDarkTheme = darkMode;
        colorGen.setDarkMode(darkMode);

        foreach (bufferName, buffer; displayBuffers)
        {
            if (bufferName in timestampTags)
            {
                timestampTags[bufferName].foreground = darkMode ? "#FFFFFF" : "#000000";
            }
            if (bufferName in systemMessageTags)
            {
                systemMessageTags[bufferName].foreground = darkMode ? "#AAAAAA" : "#555555";
            }
        }

        if (textView)
            textView.queueDraw();
    }

    void updateTheme(bool darkMode)
    {
        setTheme(darkMode);
    }

    void switchToDisplay(string display)
    {
        if (display in displayBuffers)
        {
            currentDisplay = display;
            textBuffer = displayBuffers[display];
            textView.setBuffer(textBuffer);
            scrollToEnd();
        }
    }

    void createBuffer(string name)
    {
        if (!(name in displayBuffers))
        {
            displayBuffers[name] = new TextBuffer(null);
            initializeTextTags(name);
        }
    }

    private void initializeTextTags(string bufferName)
    {
        if (!(bufferName in displayBuffers))
            return;

        auto buffer = displayBuffers[bufferName];
        auto tagTable = buffer.getTagTable();

        if (!(bufferName in timestampTags))
        {
            auto tag = new TextTag("timestamp-" ~ bufferName);
            tag.foreground = isDarkTheme ? "#FFFFFF" : "#000000";
            tagTable.add(tag);
            timestampTags[bufferName] = tag;
        }
        else
        {
            timestampTags[bufferName].foreground = isDarkTheme ? "#FFFFFF" : "#000000";
        }

        if (!(bufferName in systemMessageTags))
        {
            auto tag = new TextTag("system-" ~ bufferName);
            tag.foreground = isDarkTheme ? "#AAAAAA" : "#555555";
            tagTable.add(tag);
            systemMessageTags[bufferName] = tag;
        }
        else
        {
            systemMessageTags[bufferName].foreground = isDarkTheme ? "#AAAAAA" : "#555555";
        }

        if (!(bufferName in nicknameTags))
        {
            nicknameTags[bufferName] = null;
        }
        if (!(bufferName in modeSymbolTags))
        {
            modeSymbolTags[bufferName] = null;
        }
    }

    void appendSystemMessage(string display, string message)
    {
        appendMessage(display, formatTimestampNow(), "", "system", message);
    }

    void appendMessage(string display, string timestamp, string nickname,
            string type, string message)
    {
        logToTerminal("Appending message to display " ~ display ~ ": " ~ nickname ~ " (" ~ type ~ "): " ~ message, "INFO", "main");

        if (display.length == 0)
        {
            logToTerminal("Warning: Empty display name for message", "ERROR", "main");
            return;
        }

        if (!(display in displayBuffers))
        {
            displayBuffers[display] = new TextBuffer(null);
            initializeTextTags(display);
        }

        TextBuffer targetBuffer = displayBuffers[display];
        TextIter insertIter;
        targetBuffer.getEndIter(insertIter);

        if (display in timestampTags)
        {
            insertWithTags(targetBuffer, insertIter, timestamp ~ " ", timestampTags[display]);
        }
        else
        {
            targetBuffer.insert(insertIter, timestamp ~ " ");
        }

        targetBuffer.getEndIter(insertIter);

        char modeSymbol = '\0';
        string baseNickname = nickname;

        if (nickname.length > 0 && (nickname[0] == '@' || nickname[0] == '+' || nickname[0] == '%' || nickname[0] == '&' || nickname[0] == '~'))
        {
            modeSymbol = nickname[0];
            baseNickname = nickname[1 .. $];
        }

        switch (type)
        {
        case "message":
            if (nickname.length > 0)
            {
                if (modeSymbol != '\0')
                {
                    if (auto modeTag = getModeSymbolTag(display, modeSymbol))
                    {
                        insertWithTags(targetBuffer, insertIter, [modeSymbol].idup, modeTag);
                    }
                    else
                    {
                        targetBuffer.insert(insertIter, [modeSymbol].idup);
                    }
                }

                if (colorizeNicks)
                {
                    string nickColor = getNickColor(baseNickname);
                    if (auto nickTag = getNicknameTag(display, baseNickname, nickColor))
                    {
                        insertWithTags(targetBuffer, insertIter, baseNickname, nickTag);
                    }
                    else
                    {
                        targetBuffer.insert(insertIter, baseNickname);
                    }
                }
                else
                {
                    targetBuffer.insert(insertIter, baseNickname);
                }

                targetBuffer.getEndIter(insertIter);
                targetBuffer.insert(insertIter, ": " ~ message ~ "\n");
            }
            else
            {
                targetBuffer.insert(insertIter, message ~ "\n");
            }
            break;

        case "action":
            targetBuffer.insert(insertIter, "* ");
            targetBuffer.getEndIter(insertIter);

            if (nickname.length > 0)
            {
                if (modeSymbol != '\0')
                {
                    if (auto modeTag = getModeSymbolTag(display, modeSymbol))
                    {
                        insertWithTags(targetBuffer, insertIter, [modeSymbol].idup, modeTag);
                    }
                    else
                    {
                        targetBuffer.insert(insertIter, [modeSymbol].idup);
                    }
                }

                if (colorizeNicks)
                {
                    string nickColor = getNickColor(baseNickname);
                    if (auto nickTag = getNicknameTag(display, baseNickname, nickColor))
                    {
                        insertWithTags(targetBuffer, insertIter, baseNickname, nickTag);
                    }
                    else
                    {
                        targetBuffer.insert(insertIter, baseNickname);
                    }
                }
                else
                {
                    targetBuffer.insert(insertIter, baseNickname);
                }

                targetBuffer.getEndIter(insertIter);
                targetBuffer.insert(insertIter, " " ~ message ~ "\n");
            }
            else
            {
                targetBuffer.insert(insertIter, " " ~ message ~ "\n");
            }
            break;

        case "notice":
            targetBuffer.insert(insertIter, "-");
            targetBuffer.getEndIter(insertIter);

            if (nickname.length > 0)
            {
                if (modeSymbol != '\0')
                {
                    if (auto modeTag = getModeSymbolTag(display, modeSymbol))
                    {
                        insertWithTags(targetBuffer, insertIter, [modeSymbol].idup, modeTag);
                    }
                    else
                    {
                        targetBuffer.insert(insertIter, [modeSymbol].idup);
                    }
                }

                if (colorizeNicks)
                {
                    string nickColor = getNickColor(baseNickname);
                    if (auto nickTag = getNicknameTag(display, baseNickname, nickColor))
                    {
                        insertWithTags(targetBuffer, insertIter, baseNickname, nickTag);
                    }
                    else
                    {
                        targetBuffer.insert(insertIter, baseNickname);
                    }
                }
                else
                {
                    targetBuffer.insert(insertIter, baseNickname);
                }
                targetBuffer.getEndIter(insertIter);
                targetBuffer.insert(insertIter, "- " ~ message ~ "\n");
            }
            else
            {
                targetBuffer.insert(insertIter, "- " ~ message ~ "\n");
            }
            break;

        case "join":
        case "part":
        case "quit":
        case "kick":
        case "nick":
            if (nickname.length > 0)
            {
                if (modeSymbol != '\0')
                {
                    if (auto modeTag = getModeSymbolTag(display, modeSymbol))
                    {
                        insertWithTags(targetBuffer, insertIter, [modeSymbol].idup, modeTag);
                    }
                    else
                    {
                        targetBuffer.insert(insertIter, [modeSymbol].idup);
                    }
                }

                if (colorizeNicks)
                {
                    string nickColor = getNickColor(baseNickname);
                    if (auto nickTag = getNicknameTag(display, baseNickname, nickColor))
                    {
                        insertWithTags(targetBuffer, insertIter, baseNickname, nickTag);
                    }
                    else
                    {
                        targetBuffer.insert(insertIter, baseNickname);
                    }
                }
                else
                {
                    targetBuffer.insert(insertIter, baseNickname);
                }

                targetBuffer.getEndIter(insertIter);
                targetBuffer.insert(insertIter, " " ~ message ~ "\n");
            }
            else
            {
                targetBuffer.insert(insertIter, message ~ "\n");
            }
            break;

        case "system":
            if (display in systemMessageTags)
            {
                targetBuffer.getEndIter(insertIter);
                insertWithTags(targetBuffer, insertIter, message ~ "\n", systemMessageTags[display]);
            }
            else
            {
                targetBuffer.getEndIter(insertIter);
                targetBuffer.insert(insertIter, message ~ "\n");
            }
            break;

        default:
            if (nickname.length > 0)
            {
                if (colorizeNicks)
                {
                    string nickColor = getNickColor(baseNickname);
                    if (auto nickTag = getNicknameTag(display, baseNickname, nickColor))
                    {
                        insertWithTags(targetBuffer, insertIter, baseNickname, nickTag);
                    }
                    else
                    {
                        targetBuffer.insert(insertIter, baseNickname);
                    }
                }
                else
                {
                    targetBuffer.insert(insertIter, baseNickname);
                }
                targetBuffer.getEndIter(insertIter);
                targetBuffer.insert(insertIter, ": " ~ message ~ "\n");
            }
            else
            {
                targetBuffer.getEndIter(insertIter);
                targetBuffer.insert(insertIter, message ~ "\n");
            }
            break;
        }

        if (display == currentDisplay)
        {
            textBuffer = targetBuffer;
            textView.setBuffer(textBuffer);
            scrollToEnd();
        }
    }

    private string getNickColor(string nickname)
    {
        return colorGen.getColor(nickname);
    }

    private TextTag getNicknameTag(string bufferName, string nickname, string color)
    {
        if (!(bufferName in nicknameTags))
        {
            return null;
        }

        string tagName = "nick-" ~ nickname;
        if (tagName in nicknameTags[bufferName])
        {
            return nicknameTags[bufferName][tagName];
        }

        if (!(bufferName in displayBuffers))
            return null;

        auto buffer = displayBuffers[bufferName];
        auto tagTable = buffer.getTagTable();
        auto tag = new TextTag(tagName);
        tag.foreground = color;
        tag.weight = 700;
        tagTable.add(tag);

        nicknameTags[bufferName][tagName] = tag;
        return tag;
    }

    private TextTag getModeSymbolTag(string bufferName, char modeSymbol)
    {
        if (!(bufferName in modeSymbolTags))
            return null;

        string tagName = "mode-" ~ modeSymbol;
        if (tagName in modeSymbolTags[bufferName])
        {
            return modeSymbolTags[bufferName][tagName];
        }

        if (!(bufferName in displayBuffers))
            return null;

        auto buffer = displayBuffers[bufferName];
        auto tagTable = buffer.getTagTable();
        auto tag = new TextTag(tagName);
        tag.foreground = colorGen.getModeSymbolColor(modeSymbol, isDarkTheme);
        tag.weight = 700;
        tagTable.add(tag);

        modeSymbolTags[bufferName][tagName] = tag;
        return tag;
    }

    private void insertWithTags(TextBuffer buffer, TextIter iter, string text, TextTag[] tags...)
    {
        if (tags.length == 0)
        {
            buffer.insert(iter, text);
        }
        else
        {
            auto cBuffer = cast(GtkTextBuffer*) buffer._cPtr;
            auto cIter = cast(GtkTextIter*) iter._cPtr;
            auto cText = text.toStringz();
            auto cLength = cast(int) text.length;

            if (tags.length == 1)
            {
                auto tag1 = cast(GtkTextTag*) tags[0]._cPtr;
                gtk_text_buffer_insert_with_tags(cBuffer, cIter, cText, cLength, tag1, null);
            }
            else if (tags.length == 2)
            {
                auto tag1 = cast(GtkTextTag*) tags[0]._cPtr;
                auto tag2 = cast(GtkTextTag*) tags[1]._cPtr;
                gtk_text_buffer_insert_with_tags(cBuffer, cIter, cText, cLength, tag1, tag2, null);
            }
            else
            {
                auto tag1 = cast(GtkTextTag*) tags[0]._cPtr;
                gtk_text_buffer_insert_with_tags(cBuffer, cIter, cText, cLength, tag1, null);
            }
        }
    }

    string formatTimestampNow()
    {
        auto now = Clock.currTime();
        return "[" ~ format("%02d:%02d", now.hour, now.minute) ~ "]";
    }

    void scrollToEnd()
    {
        if (textView && textBuffer)
        {
            TextIter scrollIter;
            textBuffer.getEndIter(scrollIter);
            textView.scrollToIter(scrollIter, 0.0, true, 0.0, 1.0);
        }
    }

    TextBuffer[string] getBuffers()
    {
        return displayBuffers;
    }
}
