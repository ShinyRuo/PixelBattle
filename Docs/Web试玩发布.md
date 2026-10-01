# Web 试玩发布

本项目用 Godot 4.7.2 的 Web（单线程）预设导出。网页托管不需要自己的域名或服务器；可把导出 ZIP 上传到 itch.io 的 HTML5 项目，访客通过 itch.io 页面直接游玩。

## 本地导出

1. 安装与引擎版本一致的 Godot Web 导出模板（4.7.2.stable）。
2. 在项目根目录执行：

   ```powershell
   New-Item -ItemType Directory -Path build/web -Force | Out-Null
   F:\Godot_PJ\_engine\4.7.2\godot_console.exe --headless --path . --export-release Web build/web/index.html
   Compress-Archive -Path build/web/* -DestinationPath build/pixelbattle-web.zip -Force
   ```

3. ZIP 根目录必须直接有 `index.html`，不能再套一层 `web/`。导出使用单线程，避免托管方必须配置跨域隔离响应头。

`export_presets.cfg` 默认被 `.gitignore` 忽略；新机器需在 Godot 导出界面新建名为 `Web` 的预设，关闭线程支持，输出到 `build/web/index.html`。
可直接把 `scripts/web_export_presets.cfg` 复制为根目录的 `export_presets.cfg`，无需手动重建。

## GitHub Pages 发布

`.github/workflows/pages.yml` 在 `main` 分支推送或手动触发时，用官方 Godot 4.7.2 Linux 引擎和单线程 Web 模板在 GitHub Actions 中导出，然后把 `build/web/` 作为 Pages 产物发布。大于 GitHub 普通 Git 单文件上限的 `index.pck` 只在 Actions 中生成，不提交到仓库；Git LFS 不适用于 Pages。

首次启用：

1. 把项目源码、成品素材、`assets/fonts/`、`scripts/web_export_presets.cfg` 和 `.github/workflows/pages.yml` 提交并推送到你自己的 GitHub 仓库 `main` 分支；不要提交 `build/`、`aires/` 或 `.godot/`。
2. 在仓库 **Settings → Pages → Build and deployment → Source** 选择 **GitHub Actions**。
3. 在 **Actions → Publish Web game to GitHub Pages** 查看构建与发布结果。成功后地址通常是 `https://用户名.github.io/仓库名/`。

目标仓库：[ShinyRuo/PixelBattle](https://github.com/ShinyRuo/PixelBattle)。工作流文件就绪不等于线上已发布；以 Actions 运行结果和 Pages 实际访问为准。首次公开推送前检查所有游戏素材的发布权利。

## itch.io 发布

创建新项目，项目类型选 HTML；上传 `build/pixelbattle-web.zip`，勾选“此文件会在浏览器中运行”。设置画布 640×360，启用移动端友好选项，建议横屏游玩。先设为草稿或受限页面，在真机上测试载入、触控、性能和音频，再决定公开。

2026-10-01 的本地导出 `index.pck` 约 187 MB，另有约 40 MB 的 WASM。Web 包内置 Noto Sans SC 字体，以免手机浏览器中文显示方框；字体使用 SIL Open Font License 1.1，许可文本见 `assets/fonts/OFL.txt`。首载需要下载较多数据，手机流量、内存及 Safari 兼容性仍需真机确认。不要把“桌面浏览器可运行”视为“手机已验收”。

参考：[Godot Web 导出](https://docs.godotengine.org/en/4.5/tutorials/export/exporting_for_web.html)、[itch.io HTML5 上传说明](https://itch.io/docs/creators/html5)。
