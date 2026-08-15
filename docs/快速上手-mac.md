# 科研模式 · macOS 快速上手（生物医学文献检索助手）

一个本地运行的 AI 科研助手：接入 **DeepSeek** 大模型 + **7 个学术文献数据库**（PubMed、Europe PMC、bioRxiv/medRxiv、Crossref、OpenAlex、Semantic Scholar、arXiv），帮你做多库检索、去重排序、证据分级、反证核查，并把结果整理成带 PMID/DOI 的研究日志。

全程无需编程基础：解压 → 双击 → 粘贴 Key → 浏览器里聊天。

---

## 一、安装（约 3–5 分钟）

1. 把收到的 `bioresearch-v0.3.5-mac.zip` 解压到**任意固定位置**（安装后文件夹不要移动、不要删除）。
2. **双击 `一键安装.command`**：系统会自动打开「终端」并弹出**图形安装向导**：
   - **欢迎页** → 点「开始安装」；
   - **安装目录**：可直接输入（默认 `~/bioresearch`），或点「选择文件夹…」浏览选择；
   - **组件勾选**：「安装/更新 DeepSeek Harness」与「安装「科研模式」插件」默认全选，**已装好的会自动跳过**；
   - **DeepSeek API Key**：选填（输入框遮码、只存本机；留空可之后在网页 设置→模型 填写）；
   - 进度实时显示在终端窗口；完成后会询问是否**立即启动**并自动打开 `http://127.0.0.1:3081`。
3. 首次双击 `.command` 若系统提示「这是从互联网下载的…」，点 **「打开」** 即可。若被拦截，右键 → 打开；仍不行就在终端运行一次：`xattr -d com.apple.quarantine "一键安装.command"` 后重试。
4. 安装完成后，**「应用程序」文件夹里会出现 `deepseek-dsh`（DeepSeek 图标）**，以后双击它即可启动科研模式。
   - 文字模式（排查/服务器用）：终端运行 `bash install.sh`。
   - 重复运行向导会识别「已安装」，可直接**启动 / 重新安装 / 卸载**。

> 还没有 DeepSeek API Key？去 [platform.deepseek.com](https://platform.deepseek.com) 注册并创建 API Key（按量付费）。Key 随时可在网页 **设置 → 模型** 里更换。
> 想换安装目录？重跑「一键安装.command」→「重新安装」→ 改路径或点「选择文件夹…」。

## 二、第一次使用

1. **设置 → 模型**：确认 DeepSeek 卡片里已有 Key（安装时已自动填好）。
2. 选择模型（如 `deepseek-chat`）。
3. **选择工作区**：添加并选中你的项目文件夹（建议新建一个专门的研究目录，日志会写在这里）。
4. 新建会话时，模式默认已是 **「科研模式」**（安装器已写入默认值；已发过消息的旧会话模式固定，新建会话即可）。

## 三、示例任务

直接发给它：

> 检索 2020–2026 年关于「MYH7 突变与肥厚型心肌病」的机制研究与反证，按证据强度分级，输出带 PMID/DOI 的文献卡，写入研究日志。

或者：

> 用 literature_search 检索「TTN truncating variants 与扩张型心肌病」，限 PubMed、Europe PMC、OpenAlex 三个库，返回 10 篇，并报告哪些库失败或限流。

它会自动：制定检索策略（机制 / 方向 / 临床证据 / 反证空间）→ 调 MCP 工具检索 → 给证据分级（A–D）→ 写 `research-log/` 研究日志 → 汇报结论。

## 四、日常使用

- **启动**：双击「应用程序」里的 `deepseek-dsh`（日志在 `~/Library/Logs/bioresearch-dsh.log`）；或在终端运行 `~/bioresearch/start.sh`（Ctrl+C 停止）。
- **端口被占用**时：`~/bioresearch/start.sh 3090`。
- **研究日志**：位于你选的**工作区**目录下的 `research-log/`，每轮一个 `round-001/` 文件夹。
- **检索历史**：保存在本机 `~/.local/state/literature-search-mcp/history.jsonl`（不含摘要与密钥）。

## 五、常见问题

1. **双击 `.command` 无反应 / 提示无权限**：右键 → 打开；或终端里 `chmod +x "一键安装.command"` 后重试。
2. **提示「app 已损坏」**：只会发生在被拷贝/传输的旧 App 上；请重跑「一键安装.command」让安装器重新生成 `deepseek-dsh.app`。
3. **安装时 Node 下载很慢**：先到 [nodejs.org](https://nodejs.org) 手动安装 Node.js 22+（LTS），再重跑安装向导，会自动使用系统 Node。
4. **Key 校验失败（401）**：Key 复制错了（多空格/少字符）。重跑安装向导，或在网页 **设置 → 模型** 里重填。
5. **网页提示 MISSING_CREDENTIAL**：**设置 → 模型** 里给 DeepSeek 填 Key 并保存，立即生效，无需重启。
6. **MCP 没连上 / 检索报错**：终端运行 `node ~/bioresearch/literature-search-mcp/dist/server.js` 看报错；最常见是 Node 过旧或依赖未装全，重跑安装向导即可修复。
7. **只有部分数据库出结果**：正常。每次检索结果里有 `source_statuses` 字段：`ok` 成功、`empty` 无匹配、`rate_limited` 被限流、`timeout` 超时。单库失败不影响整体。
8. **升级新版**：收到新 zip 后解压覆盖旧位置，重跑「一键安装.command」→「重新安装」（不会动你的 Key 和研究日志）。
9. **卸载**：双击 `卸载.command`，或重跑「一键安装.command」→「卸载」。DSH 本体可用 `npm rm -g @deepseek-ai/dsh` 移除。
10. **「科研模式」打不开 / 点击后弹回标准模式**：DSH 规定**已发送过消息的会话模式固定**，不能中途切换——新建一个会话即可（安装器已把「科研模式」设为默认）。若新建会话仍失败，把终端输出发给发你安装包的人定位。

## 六、隐私与成本

- 你的 DeepSeek API Key 只保存在本机 `~/.dsh/.credentials.yaml`（权限 0600），不会上传、不会打进安装包、不会写进日志。
- 模型调用走你的 DeepSeek 账户，按量计费；文献检索走公共学术数据库接口，无需额外付费。
- 所有数据默认只在本机（127.0.0.1），不会开放给局域网或公网。
