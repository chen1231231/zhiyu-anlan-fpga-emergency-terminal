# 第三方依赖与素材说明

本文件记录当前能从交付目录识别的来源边界，不代表已获得全部第三方再分发许可。

| 位置 / 类型 | 来源与使用说明 |
| --- | --- |
| `portable_project/dependencies/dependencies/lesson36_build/` | 开发板参考例程相关模块，含 PLL、FIFO、SDRAM 加密 IP 等；原有文件声明保持不变。 |
| `portable_project/dependencies/dependencies/official_hdmi/` | 官方 HDMI 相关参考模块及加密 IP；需遵守原供应方使用、分发条款。 |
| `portable_project/dependencies/rtl/`、`dependencies/risk_prototypes/`（均在 `portable_project` 下） | 项目继承的参考模块和集成依赖，不应统一声称为团队原创；具体以文件内声明为准。 |
| `TF_CARD_ROOT/*.PCM` 及工程内同名副本 | 由用户提供的中文播报 MP3、警报 OGG 转码适配。当前没有随素材附带的公开再分发授权证明。 |
| `TF_CARD_ROOT/*.BMP`、预览图及工程内副本 | 项目制作与集成的界面素材；涉及字体、图形等权利时仍应核实来源条款。 |
| Tang Dynasty、FPGA 下载工具、Icarus Verilog 等 | 外部构建/测试工具，不随本仓库提供安装程序。 |

目前未添加覆盖整个仓库的 MIT、Apache、GPL 等统一许可证。将仓库设为 Public 仅改变可见性，不会自动解决版权或许可问题。公开前应核实厂商参考代码、IP 与音频等素材的分发条款；若不允许分发，可移除受限文件并说明合法获取及放置方法，或替换成获得授权的实现/素材后重新验证。

当前 README 是本次整理新增的仓库首页；历史使用说明、验证记录和交付清单保留，里面可能出现当时开发环境的本地路径或旧打包名称，请以首页的仓库结构和命令为入口。
