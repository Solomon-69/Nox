using System.Drawing.Drawing2D;

namespace Nox;

/// <summary>The tray switch: a small pill with its knob left (light) or right and filled (dark).</summary>
internal static class Glyph
{
    public static void Draw(Graphics g, float px, bool dark, Color color)
    {
        var w = px * 0.92f;
        var h = px * 0.56f;
        var x = (px - w) / 2f;
        var y = (px - h) / 2f;
        var stroke = Math.Max(1f, px / 16f * 1.25f);
        var knob = h - stroke * 2.6f;
        if (dark)
        {
            // Filled pill with the knob cut out on the right.
            using var shape = Pill(new RectangleF(x, y, w, h));
            shape.FillMode = FillMode.Alternate;
            shape.AddEllipse(x + w - h + (h - knob) / 2, y + (h - knob) / 2, knob, knob);
            using var brush = new SolidBrush(color);
            g.FillPath(brush, shape);
        }
        else
        {
            using var pen = new Pen(color, stroke);
            using var inner = Pill(new RectangleF(x + stroke / 2, y + stroke / 2, w - stroke, h - stroke));
            g.DrawPath(pen, inner);
            using var brush = new SolidBrush(color);
            g.FillEllipse(brush, x + (h - knob) / 2, y + (h - knob) / 2, knob, knob);
        }
    }

    private static GraphicsPath Pill(RectangleF r)
    {
        var p = new GraphicsPath();
        p.AddArc(r.Left, r.Top, r.Height, r.Height, 90, 180);
        p.AddArc(r.Right - r.Height, r.Top, r.Height, r.Height, 270, 180);
        p.CloseFigure();
        return p;
    }
}
