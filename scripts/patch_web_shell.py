"""Add a portrait-phone rotation prompt to a generated Godot Web shell."""

from pathlib import Path
import sys


def main() -> None:
    path = Path(sys.argv[1])
    html = path.read_text(encoding="utf-8")
    if 'id="orientation-help"' in html:
        return
    html = html.replace(
        'content="width=device-width, user-scalable=no, initial-scale=1.0"',
        'content="width=device-width, initial-scale=1.0, viewport-fit=cover, user-scalable=no"',
    )
    styles = """
#orientation-help { display: none; }
@media (orientation: portrait) and (max-width: 900px) {
  #orientation-help {
    position: fixed; inset: 0; z-index: 1000; display: flex;
    flex-direction: column; align-items: center; justify-content: center;
    gap: 1rem; padding: 2rem; box-sizing: border-box;
    background: #141b29; color: #f4f5f8; text-align: center;
    font: 1.2rem sans-serif;
  }
  #orientation-help button {
    min-height: 48px; padding: 0.5rem 1rem; border-radius: 8px;
    border: 1px solid #809fd5; background: #29446c; color: white;
    font: inherit; touch-action: manipulation;
  }
}
"""
    html = html.replace("</style>", styles + "\n</style>", 1)
    prompt = """
<div id="orientation-help">
  <span>请将手机横过来游玩</span>
  <button id="try-landscape" type="button">尝试横屏全屏</button>
</div>
"""
    html = html.replace('<script src="index.js"></script>', prompt + '\n<script src="index.js"></script>', 1)
    behavior = """
<script>
document.getElementById('try-landscape').addEventListener('click', async () => {
  try {
    await document.documentElement.requestFullscreen();
    if (screen.orientation && screen.orientation.lock) {
      await screen.orientation.lock('landscape');
    }
  } catch (_) {
    // Some mobile browsers do not allow orientation locking; physical rotation still works.
  }
});
</script>
"""
    html = html.replace("</body>", behavior + "\n</body>", 1)
    path.write_text(html, encoding="utf-8")


if __name__ == "__main__":
    main()
