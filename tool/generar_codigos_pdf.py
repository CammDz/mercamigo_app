# -*- coding: utf-8 -*-
"""Genera mercamigo_codigos_de_barras.pdf con las etiquetas del catalogo.

Lee los productos y sus codigos desde Supabase (API REST publica, clave
publicable) y dibuja una etiqueta imprimible por producto:

    nombre  ->  codigo de barras Code 128  ->  codigo legible

Uso:
    python tool/generar_codigos_pdf.py [salida.pdf]

Variables de entorno opcionales:
    SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY
"""
import datetime
import json
import os
import sys
import urllib.parse
import urllib.request

from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.pdfbase.pdfmetrics import stringWidth
from reportlab.pdfgen import canvas
from reportlab.graphics.barcode import code128

URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
KEY = os.environ.get("SUPABASE_PUBLISHABLE_KEY", "")
if not URL or not KEY:
    raise SystemExit(
        "Define SUPABASE_URL y SUPABASE_PUBLISHABLE_KEY (ver .env.example)."
    )

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    ROOT, "mercamigo_codigos_de_barras.pdf"
)

# Productos de prueba que no forman parte del catalogo comercial.
EXCLUIR = {"Pantalla", "Pantalla2", "Test"}


def fetch_products():
    query = urllib.parse.urlencode(
        {
            "select": "nombre,activo,codigos_producto(codigo,tipo)",
            "activo": "eq.true",
            "order": "nombre.asc",
        }
    )
    req = urllib.request.Request(
        f"{URL}/rest/v1/productos?{query}",
        headers={"apikey": KEY, "Authorization": f"Bearer {KEY}"},
    )
    with urllib.request.urlopen(req, timeout=45) as r:
        data = json.loads(r.read().decode("utf-8"))

    items = []
    for p in data:
        name = (p.get("nombre") or "").strip()
        if not name or name in EXCLUIR:
            continue
        codes = [c for c in (p.get("codigos_producto") or []) if c.get("codigo")]
        if not codes:
            continue
        # Preferimos el codigo de barras sobre cualquier otro tipo.
        codes.sort(key=lambda c: 0 if (c.get("tipo") == "barras") else 1)
        items.append((name, str(codes[0]["codigo"]).strip()))
    items.sort(key=lambda x: x[0].casefold())
    return items


def wrap(text, font, size, max_width, max_lines=2):
    words = text.split()
    lines, current = [], ""
    for word in words:
        probe = (current + " " + word).strip()
        if stringWidth(probe, font, size) <= max_width or not current:
            current = probe
        else:
            lines.append(current)
            current = word
    if current:
        lines.append(current)
    if len(lines) > max_lines:
        lines = lines[:max_lines]
        while lines and stringWidth(lines[-1] + "\u2026", font, size) > max_width:
            lines[-1] = lines[-1][:-1]
        lines[-1] += "\u2026"
    return lines


def build(items, path):
    page_w, page_h = A4
    margin_x, margin_top, margin_bottom = 12 * mm, 16 * mm, 14 * mm
    cols, rows = 3, 7
    gap_x, gap_y = 3 * mm, 3 * mm
    label_w = (page_w - 2 * margin_x - (cols - 1) * gap_x) / cols
    label_h = (page_h - margin_top - margin_bottom - (rows - 1) * gap_y) / rows
    per_page = cols * rows
    pages = (len(items) + per_page - 1) // per_page
    today = datetime.date.today().strftime("%d/%m/%Y")

    c = canvas.Canvas(path, pagesize=A4)
    c.setTitle("Mercamigo - Codigos de barras")
    c.setAuthor("Mercamigo")
    c.setSubject("Etiquetas imprimibles de codigos de barras del catalogo")

    for page in range(pages):
        # Encabezado
        c.setFillColorRGB(0.12, 0.15, 0.2)
        c.setFont("Helvetica-Bold", 15)
        c.drawString(margin_x, page_h - 11 * mm, "Mercamigo")
        c.setFont("Helvetica", 9)
        c.setFillColorRGB(0.35, 0.38, 0.44)
        subtitle_x = margin_x + stringWidth("Mercamigo", "Helvetica-Bold", 15) + 4 * mm
        c.drawString(subtitle_x, page_h - 10.6 * mm, "Catalogo de codigos de barras")
        c.drawRightString(
            page_w - margin_x,
            page_h - 10.6 * mm,
            f"Generado el {today}  |  {len(items)} productos",
        )
        c.setStrokeColorRGB(0.85, 0.87, 0.9)
        c.setLineWidth(0.6)
        c.line(margin_x, page_h - 14 * mm, page_w - margin_x, page_h - 14 * mm)

        start = page * per_page
        for index, (name, code) in enumerate(items[start:start + per_page]):
            col = index % cols
            row = index // cols
            x = margin_x + col * (label_w + gap_x)
            y_top = page_h - margin_top - row * (label_h + gap_y)
            y = y_top - label_h

            # Marco punteado de la etiqueta
            c.setDash(1.2, 1.8)
            c.setStrokeColorRGB(0.78, 0.8, 0.84)
            c.roundRect(x, y, label_w, label_h, 2 * mm, stroke=1, fill=0)
            c.setDash()

            inner_w = label_w - 5 * mm
            # Nombre (maximo 2 lineas)
            c.setFillColorRGB(0.12, 0.15, 0.2)
            c.setFont("Helvetica-Bold", 7.6)
            lines = wrap(name, "Helvetica-Bold", 7.6, inner_w, 2)
            text_y = y_top - 5.2 * mm
            for line in lines:
                c.drawString(x + 2.5 * mm, text_y, line)
                text_y -= 3.4 * mm

            # Codigo de barras Code 128
            bar_height = 9.5 * mm
            bar_y = y + 5.6 * mm
            try:
                bc = code128.Code128(
                    code,
                    barWidth=0.26 * mm,
                    barHeight=bar_height,
                    humanReadable=False,
                    quiet=True,
                )
                bw = bc.width
                if bw > inner_w:
                    factor = inner_w / bw
                    bc.barWidth = bc.barWidth * factor
                    bw = bc.width
                bc.drawOn(c, x + (label_w - bw) / 2, bar_y)
            except Exception as exc:  # noqa: BLE001
                c.setFont("Helvetica", 7)
                c.setFillColorRGB(0.7, 0.1, 0.1)
                c.drawCentredString(x + label_w / 2, bar_y + 3 * mm, f"Error: {exc}")

            # Codigo legible
            c.setFillColorRGB(0.05, 0.05, 0.05)
            c.setFont("Courier-Bold", 9)
            c.drawCentredString(x + label_w / 2, y + 1.9 * mm, code)

        # Pie de pagina
        c.setFont("Helvetica", 8)
        c.setFillColorRGB(0.45, 0.48, 0.53)
        c.drawString(margin_x, 8 * mm, "Mercamigo - documento generado automaticamente")
        c.drawRightString(
            page_w - margin_x, 8 * mm, f"Pagina {page + 1} de {pages}"
        )
        c.showPage()

    c.save()


def main():
    items = fetch_products()
    if not items:
        raise SystemExit("No se encontraron productos con codigo.")
    build(items, OUTPUT)
    print(f"PDF generado: {OUTPUT}")
    print(f"Productos incluidos: {len(items)}")
    for name, code in items:
        print(f"  {code}  {name}")


if __name__ == "__main__":
    main()
