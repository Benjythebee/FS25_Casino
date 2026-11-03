"""Generate FS25_Casino/gui/CasinoFrame.xml (the roulette page layout).

The board has ~50 cells with the same inner structure, so the XML is generated rather than hand-written.
Coordinates are pixels in the 1920x1080 reference resolution, measured from the top left of the content area.

    python tools/gen_frame.py
"""

from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "FS25_Casino" / "gui" / "CasinoFrame.xml"

RED = {1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36}

CELL_W, CELL_H, GAP = 72, 64, 2
BOARD_Y = 372
NUM_X = 66  # first number column, right of the zero
NUM_SEATS = 5
NUM_HISTORY = 12
NUM_BET_LINES = 10
WHEEL_SIZE = 300
INFO_X = 330  # left edge of the texts and controls right of the wheel

lines = []


def out(depth, text):
    lines.append("    " * depth + text)


def box(x, y, w, h):
    return f'position="{x}px {-y}px" size="{w}px {h}px"'


def cell(depth, key, x, y, w, h, profile, label, label_size=None):
    """A clickable board cell: colour, winning highlight, label, stake, seat markers, click area."""
    out(depth, f'<Bitmap profile="{profile}" id="casinoCell_{key}" {box(x, y, w, h)}>')
    out(depth + 1, f'<Bitmap profile="casinoCellWin" name="win" {box(0, 0, w, h)}/>')
    size = f' textSize="{label_size}px"' if label_size else ""
    out(depth + 1, f'<Text profile="casinoCellLabel" name="label" text="{label}"{size} {box(0, 0, w, h - 18)}/>')
    out(depth + 1, f'<Text profile="casinoCellStake" name="stake" text="" {box(0, h - 20, w, 18)}/>')
    for s in range(1, NUM_SEATS + 1):
        out(depth + 1, f'<Bitmap profile="casinoDot{s}" name="dot{s}" {box(3 + (s - 1) * 11, 3, 9, 9)}/>')
    out(depth + 1, f'<Button profile="casinoCellHit" name="{key}" onClick="onClickCell" {box(0, 0, w, h)}/>')
    out(depth, "</Bitmap>")


def button(depth, element_id, name, x, y, w, h, callback, text=""):
    out(depth, f'<Button profile="casinoButton" id="{element_id}" name="{name}" onClick="{callback}" text="{text}" {box(x, y, w, h)}/>')


def text(depth, element_id, profile, x, y, w, h, value=""):
    id_attr = f' id="{element_id}"' if element_id else ""
    out(depth, f'<Text profile="{profile}"{id_attr} text="{value}" {box(x, y, w, h)}/>')


def board(d):
    # zero spans the three rows
    cell(d, "n0", 0, BOARD_Y, NUM_X - GAP, 3 * CELL_H + 2 * GAP, "casinoCellGreen", "0", 30)

    for n in range(1, 37):
        col = (n - 1) // 3
        row = 2 - (n - 1) % 3  # 0 = top row (3, 6 ... 36)
        x = NUM_X + col * (CELL_W + GAP)
        y = BOARD_Y + row * (CELL_H + GAP)
        cell(d, f"n{n}", x, y, CELL_W, CELL_H, "casinoCellRed" if n in RED else "casinoCellBlack", str(n))

    col_x = NUM_X + 12 * (CELL_W + GAP)
    for c in (1, 2, 3):
        y = BOARD_Y + (3 - c) * (CELL_H + GAP)
        cell(d, f"col{c}", col_x, y, 100, CELL_H, "casinoCellOutside", "2 to 1", 18)

    dozen_y = BOARD_Y + 3 * (CELL_H + GAP)
    dozen_w = 4 * (CELL_W + GAP) - GAP
    for k, label in enumerate(("1st 12", "2nd 12", "3rd 12")):
        cell(d, f"doz{k + 1}", NUM_X + k * (dozen_w + GAP), dozen_y, dozen_w, 50, "casinoCellOutside", label, 20)

    even_y = dozen_y + 52
    even_w = (3 * dozen_w + 2 * GAP - 5 * GAP) // 6
    simple = (("low", "1-18", "casinoCellOutside"), ("even", "$l10n_casino_bet_even", "casinoCellOutside"),
              ("red", "$l10n_casino_bet_red", "casinoCellRed"), ("black", "$l10n_casino_bet_black", "casinoCellBlack"),
              ("odd", "$l10n_casino_bet_odd", "casinoCellOutside"), ("high", "19-36", "casinoCellOutside"))
    for k, (key, label, profile) in enumerate(simple):
        cell(d, key, NUM_X + k * (even_w + GAP), even_y, even_w, 50, profile, label, 18)


def wheel(d):
    """Wheel and ball are two textures of the same size rotated by CasinoFrame; the pointer and hub stay still."""
    y = 56
    out(d, f'<Bitmap profile="casinoWheel" id="casinoWheel" {box(0, y, WHEEL_SIZE, WHEEL_SIZE)}/>')
    out(d, f'<Bitmap profile="casinoWheel" id="casinoBall" {box(0, y, WHEEL_SIZE, WHEEL_SIZE)}/>')
    out(d, f'<Bitmap profile="casinoPointer" {box(WHEEL_SIZE // 2 - 6, y - 8, 12, 30)}/>')
    hub = 70
    text(d, "casinoHubText", "casinoHub", (WHEEL_SIZE - hub) // 2, y + (WHEEL_SIZE - hub) // 2, hub, hub)


def left_column(d):
    for t in range(1, 4):
        button(d, f"casinoTableBtn{t}", f"t{t}", (t - 1) * 214, 0, 204, 44, "onClickTable")

    wheel(d)

    w = 1060 - INFO_X
    text(d, "casinoStatusText", "casinoStatus", INFO_X, 66, w, 40)
    text(d, "casinoAccessText", "casinoAccess", INFO_X, 112, w, 30)

    text(d, None, "casinoSmallLabel", INFO_X, 160, 76, 34, "$l10n_casino_history")
    for h in range(1, NUM_HISTORY + 1):
        out(d, f'<Bitmap profile="casinoPocket" id="casinoHist{h}" {box(INFO_X + 80 + (h - 1) * 44, 160, 40, 34)}>')
        out(d + 1, f'<Text profile="casinoHistLabel" name="label" text="" {box(0, 0, 40, 34)}/>')
        out(d, "</Bitmap>")

    text(d, None, "casinoSmallLabel", INFO_X, 222, 76, 44, "$l10n_casino_chip")
    for c in range(1, 5):
        button(d, f"casinoChipBtn{c}", f"c{c}", INFO_X + 80 + (c - 1) * 148, 222, 140, 44, "onClickChip")

    button(d, "casinoClearBtn", "clear", INFO_X + 80, 284, 210, 44, "onClickClear", "$l10n_casino_clearBets")
    button(d, "casinoRebetBtn", "rebet", INFO_X + 300, 284, 210, 44, "onClickRebet", "$l10n_casino_rebet")

    text(d, "casinoMessageText", "casinoMessage", INFO_X, 336, w, 30)

    board(d)


def right_column(d):
    x0 = 1090
    row_w = 404
    text(d, None, "casinoHeading", x0, 0, 460, 44, "$l10n_casino_players")
    for s in range(1, NUM_SEATS + 1):
        y = 50 + (s - 1) * 82
        out(d, f'<Bitmap profile="casinoSeatBg" id="casinoSeat{s}" {box(x0, y, row_w, 76)}>')
        out(d + 1, f'<Bitmap profile="casinoSeatSwatch{s}" name="swatch" {box(8, 8, 12, 60)}/>')
        out(d + 1, f'<Text profile="casinoSeatName" name="name" text="" {box(32, 6, row_w - 40, 30)}/>')
        out(d + 1, f'<Text profile="casinoSeatInfo" name="info" text="" {box(32, 38, row_w - 40, 30)}/>')
        out(d + 1, f'<Button profile="casinoSeatHit" name="s{s}" onClick="onClickSeatRow" {box(0, 0, row_w, 76)}/>')
        out(d, "</Bitmap>")
        # leave button, shown next to the local player's own seat
        out(d, f'<Button profile="casinoLeaveButton" id="casinoLeaveBtn{s}" name="l{s}" onClick="onClickLeave" {box(x0 + row_w + 8, y + 14, 48, 48)}>')
        out(d + 1, f'<Bitmap profile="casinoLeaveIcon" name="icon" {box(8, 8, 32, 32)}/>')
        out(d, "</Button>")

    text(d, "casinoBalanceText", "casinoInfo", x0, 466, 460, 30)
    text(d, "casinoStakeText", "casinoInfo", x0, 498, 460, 30)
    text(d, None, "casinoHeading", x0, 538, 460, 32, "$l10n_casino_yourBets")
    for b in range(1, NUM_BET_LINES + 1):
        text(d, f"casinoBetLine{b}", "casinoBetLine", x0, 574 + (b - 1) * 24, 460, 24)


def main():
    out(0, '<?xml version="1.0" encoding="utf-8" standalone="no" ?>')
    out(0, "<!-- Generated by tools/gen_frame.py, do not edit by hand -->")
    out(0, '<GUI name="casinoFrame">')
    out(1, '<GuiElement profile="fs25_menuContainer">')
    out(2, '<GuiElement profile="fs25_menuHeaderPanel">')
    out(3, '<Bitmap profile="fs25_menuHeaderIconBg">')
    out(4, '<Bitmap profile="casinoHeaderIcon"/>')
    out(3, "</Bitmap>")
    out(3, '<Text profile="fs25_menuHeaderTitle" id="casinoHeaderTitle" text="$l10n_ui_casinoFrame"/>')
    out(2, "</GuiElement>")
    out(2, '<GuiElement profile="casinoContent">')
    left_column(3)
    right_column(3)
    out(2, "</GuiElement>")
    out(1, "</GuiElement>")
    out(0, "</GUI>")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {OUT} ({len(lines)} lines)")


if __name__ == "__main__":
    main()
