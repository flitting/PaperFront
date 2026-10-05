"""Generate distinct transparent naval cards and portrait rasters."""
from __future__ import annotations
from pathlib import Path
import subprocess

CARDS = Path(__file__).resolve().parents[1] / "assets" / "cards"
COLORS = {
    "rivet": ("#bb4034", "#603837", "#e0b373"),
    "kestrel": ("#2865a5", "#244b71", "#b9d2d9"),
    "iron": ("#bb963e", "#655746", "#dfc47e"),
    "sky": ("#67578b", "#453968", "#d8c5ed"),
}
STATES = ("idle", "move", "attack", "hit", "death")


def svg(faction: str, role: str, state: str) -> str:
    base, dark, trim = COLORS[faction]
    ink = "#382a22"
    shift = 8 if state == "move" else -8 if state == "hit" else 0
    pieces: list[str] = []
    if role == "shipyard":
        shape = '<path d="M36 270V116L78 64H218L247 108V263Z" fill="%s"/><path d="M245 232V150H344V270H245Z" fill="#987b52"/><path d="M35 260H345V286H35Z" fill="%s"/>' % (base, dark)
        pieces.append(shape)
        pieces.append('<path d="M258 132V69H276V132M276 69H332M332 69V245" fill="none" stroke="%s" stroke-width="13" stroke-linejoin="round"/>' % ink)
        for x in (257, 326):
            pieces.append(f'<path d="M{x} 240V284" stroke="{ink}" stroke-width="12"/>')
        pieces.append(f'<path d="M66 94H216V113H66Z" fill="{trim}"/>')
        if faction == "rivet": pieces.append(f'<path d="M52 143H83V241H52ZM193 143H224V241H193Z" fill="{dark}"/>')
        elif faction == "kestrel": pieces.append(f'<path d="M74 139V78H86V139M178 139V78H190V139M68 82H196" stroke="{trim}" stroke-width="10" fill="none"/>')
        elif faction == "iron": pieces.append(f'<path d="M101 64V35H189V64M120 37V83" stroke="{dark}" stroke-width="12" fill="none"/>')
        else: pieces.append(f'<path d="M78 69V29H89V69M180 69V29H191V69M77 31H192" stroke="{trim}" stroke-width="9" fill="none"/>')
    else:
        length = 280 if role == "transport" else 307 if role == "frigate" else 324
        stern = 29 if role == "transport" else 21
        bow = stern + length
        hull_path = f'M{stern} 197 Q{stern-5} 179 {stern+21} 174 H{bow-42} L{bow} 196 L{bow-19} 254 H{stern+18}Z'
        pieces.append(f'<path d="{hull_path}" fill="{base}" stroke="{ink}" stroke-width="8" stroke-linejoin="round"/>')
        pieces.append(f'<path d="M{stern+18} 218H{bow-14}L{bow-20} 245H{stern+16}Z" fill="{dark}"/>')
        pieces.append(f'<path d="M{stern+31} 177H{bow-47}M{stern+26} 210H{bow-20}" stroke="{trim}" stroke-width="7"/>')
        if role == "transport":
            pieces.append(f'<path d="M91 119H240V190H91Z" fill="{dark}" stroke="{ink}" stroke-width="7"/><path d="M90 111H244V127H90Z" fill="{trim}"/>')
            pieces.append(f'<path d="M245 181L303 185L322 210H250Z" fill="{trim}" stroke="{ink}" stroke-width="5"/>')
            for x in (119, 156, 193): pieces.append(f'<path d="M{x} 133V181" stroke="{trim}" stroke-width="7"/>')
        else:
            pieces.append(f'<path d="M88 106H186L203 183H74Z" fill="{base}" stroke="{ink}" stroke-width="6"/><path d="M113 120H178V145H113Z" fill="#759591"/>')
            pieces.append(f'<path d="M203 139H259V183H203Z" fill="{dark}" stroke="{ink}" stroke-width="6"/><path d="M222 141V121H246V141" fill="{trim}"/>')
            pieces.append(f'<path d="M246 145L333 135V153L246 165Z" fill="{trim}" stroke="{ink}" stroke-width="6"/>')
        if faction == "rivet":
            pieces.append(f'<path d="M275 179L{bow} 192L{bow-10} 213L280 214Z" fill="{dark}"/><path d="M69 190H265" stroke="{trim}" stroke-width="9"/>')
        elif faction == "kestrel":
            pieces.append(f'<path d="M118 110V76H139V110M161 110V76H182V110M108 80H192" fill="none" stroke="{trim}" stroke-width="9"/>')
        elif faction == "iron":
            pieces.append(f'<path d="M77 108V53H89V108M88 54H199M199 54V151" fill="none" stroke="{dark}" stroke-width="11"/><path d="M59 198H92M202 198H229" stroke="{trim}" stroke-width="9"/>')
        else:
            for x in (104, 154): pieces.append(f'<path d="M{x} 119V71H{x+8}V119M{x} 71H{x+51}" stroke="{trim}" stroke-width="8" fill="none"/>')
        pieces.append(f'<path d="M76 165H108V180H76Z" fill="#e7ad42" stroke="{ink}" stroke-width="3"/>')
    if state == "attack" and role not in ("transport", "shipyard"):
        pieces.append('<path d="M332 124L368 102L359 130L377 148L351 145L361 173L332 153Z" fill="#f4cc6d" stroke="#382a22" stroke-width="4"/>')
    if state == "hit": pieces.append('<path d="M201 175L181 197L204 209L188 225" fill="none" stroke="#f4d7a0" stroke-width="7"/>')
    if state == "death": pieces.append('<path d="M160 167L188 193L171 215L204 242" fill="none" stroke="#382a22" stroke-width="11"/>')
    if state == "move" and role != "shipyard":
        for y in (258, 270): pieces.append(f'<path d="M{stern+27} {y}Q188 {y+9} {bow-26} {y}" fill="none" stroke="#7fa9ba" stroke-width="5"/>')
    parts = "".join(pieces)
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="380" height="320" viewBox="0 0 380 320"><g transform="translate({shift} 0)">{parts}</g></svg>\n'


def main() -> None:
    CARDS.mkdir(parents=True, exist_ok=True)
    for faction in COLORS:
        for role in ("shipyard", "transport", "frigate", "signature"):
            for state in STATES:
                if role == "shipyard" and state not in ("idle", "death"):
                    continue
                stem = f"{faction}_{role}" if role == "shipyard" else f"{faction}_ship_{role}"
                path = CARDS / f"{stem}_{state}.svg"
                path.write_text(svg(faction, role, state), encoding="utf-8")
            portrait = CARDS / f"{stem}_portrait.png"
            subprocess.run(["convert", "-background", "none", str(CARDS / f"{stem}_idle.svg"), "-resize", "512x384", str(portrait)], check=True)


if __name__ == "__main__":
    main()
