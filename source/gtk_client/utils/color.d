module gtk_client.utils.color;

import std.string;
import std.conv;
import std.algorithm;
import std.math;

class ColorGenerator
{
    private bool darkMode;

    this(bool dark = true)
    {
        darkMode = dark;
    }

    void setDarkMode(bool dark)
    {
        darkMode = dark;
    }

    bool isDarkMode() const
    {
        return darkMode;
    }

    string getColor(string nickname)
    {
        string normalized = nickname.strip().toLower();
        if (normalized.length == 0)
            normalized = "user";

        uint hash1 = 0;
        uint hash2 = 0x811c9dc5u;

        for (int i = 0; i < normalized.length; i++)
        {
            char c = normalized[i];
            uint pos = i + 1;
            hash1 = ((hash1 << 5) + hash1) + c * pos;
            hash2 ^= c * (pos * 31);
            hash2 *= 0x01000193u;
        }

        uint combined = hash1 ^ hash2;
        combined ^= combined >> 16;
        combined *= 0x85ebca6bu;
        combined ^= combined >> 13;
        combined *= 0xc2b2ae35u;
        combined ^= combined >> 16;

        float hue = cast(float)(combined % 360);
        hue = hue * 0.618033988749895f;
        hue = fmod(hue, 360.0f);

        if (darkMode)
        {
            float saturation = 0.85f;
            float lightness = 0.65f;
            uint varHash = (combined >> 8) & 0xFF;
            saturation += 0.1f * (cast(float) varHash / 255.0f);
            lightness += 0.1f * (cast(float)((combined >> 16) & 0xFF) / 255.0f);
            return hslToHex(hue, saturation, lightness);
        }
        else
        {
            float saturation = 0.9f;
            float lightness = 0.45f;
            uint varHash = (combined >> 8) & 0xFF;
            saturation += 0.05f * (cast(float) varHash / 255.0f);
            lightness += 0.1f * (cast(float)((combined >> 16) & 0xFF) / 255.0f);
            return hslToHex(hue, saturation, lightness);
        }
    }

    string getModeSymbolColor(char modeSymbol, bool darkMode)
    {
        switch (modeSymbol)
        {
        case '@': return darkMode ? "#FF4444" : "#D32F2F";
        case '%': return darkMode ? "#FF9800" : "#F57C00";
        case '+': return darkMode ? "#4CAF50" : "#388E3C";
        case '&': return darkMode ? "#2196F3" : "#1976D2";
        case '~': return darkMode ? "#9C27B0" : "#7B1FA2";
        default: return darkMode ? "#CCCCCC" : "#666666";
        }
    }

    private string hslToHex(float h, float s, float l)
    {
        h = fmod(h, 360.0f);
        if (h < 0) h += 360.0f;
        s = s < 0.0f ? 0.0f : (s > 1.0f ? 1.0f : s);
        l = l < 0.0f ? 0.0f : (l > 1.0f ? 1.0f : l);

        float c = (1.0f - abs(2.0f * l - 1.0f)) * s;
        float x = c * (1.0f - abs(fmod(h / 60.0f, 2.0f) - 1.0f));
        float m = l - c / 2.0f;
        float r, g, b;

        if (h < 60)
        {
            r = c;
            g = x;
            b = 0;
        }
        else if (h < 120)
        {
            r = x;
            g = c;
            b = 0;
        }
        else if (h < 180)
        {
            r = 0;
            g = c;
            b = x;
        }
        else if (h < 240)
        {
            r = 0;
            g = x;
            b = c;
        }
        else if (h < 300)
        {
            r = x;
            g = 0;
            b = c;
        }
        else
        {
            r = c;
            g = 0;
            b = x;
        }
        r += m;
        g += m;
        b += m;
        r = r < 0.0f ? 0.0f : (r > 1.0f ? 1.0f : r);
        g = g < 0.0f ? 0.0f : (g > 1.0f ? 1.0f : g);
        b = b < 0.0f ? 0.0f : (b > 1.0f ? 1.0f : b);

        int ri = cast(int)(r * 255);
        int gi = cast(int)(g * 255);
        int bi = cast(int)(b * 255);
        return "#" ~ format("%02X%02X%02X", ri, gi, bi);
    }
}
