---
name: literature-review
description: 当需要用学术文献验证研究问题、假说或具体声明时使用——制定检索策略、调用文献检索 MCP 工具（literature_search / literature_sources / literature_get_fulltext）、给证据分级、批判性阅读论文、寻找反证或竞争性假说。本预设中每一轮文献工作的规范流程。
---

# 文献综述：用多数据库证据检验研究问题

你的任务是把用户的研究问题逐条转化为检索，在文献中找到支持与反对的证据，并给证据分级。**没有 PMID 或 DOI 的证据不算证据。**

## 1. 工具清单（本预设的文献检索 MCP）

模型可见三个工具，统一以 `mcp__literature__` 开头：

| 工具 | 用途 |
|---|---|
| `mcp__literature__literature_sources` | 列出 7 个数据库、各自能力与局限、可选凭据配置状态。不确定来源覆盖面时先调它。 |
| `mcp__literature__literature_search` | 并行检索 PubMed、Europe PMC、bioRxiv/medRxiv、Crossref、OpenAlex、Semantic Scholar、arXiv，去重后用倒数排名融合（RRF）排序。 |
| `mcp__literature__literature_get_fulltext` | 按 `pmcid` / `pmid` / `doi` 取 Europe PMC 开放获取子集的全文（标题、摘要、结构化分节、拼接纯文本）。 |

### literature_search 参数

| 参数 | 类型 | 默认 | 说明 |
|---|---:|---|---|
| `query` | string | 必填 | 检索表达式。富语法（字段限定、通配符、布尔）对 PubMed（`[Field]`）、Europe PMC（`FIELD:`）、arXiv（`field:`）原样透传；Crossref、OpenAlex、Semantic Scholar、bioRxiv 收到自动清洗后的关键词形式。 |
| `limit` | 1–50 | 10 | 融合后返回条数上限。 |
| `sources` | 数组 | 全部 7 库 | `pubmed`、`europepmc`、`biorxiv`、`crossref`、`openalex`、`semantic-scholar`、`arxiv`。 |
| `year_from` / `year_to` | 整数 | 不限 | 发表年份闭区间。 |
| `open_access` | 布尔 | 不限 | 只要开放获取或有 PDF 证据的文献。 |
| `abstract_max_chars` | 1–3000 | 3000 | 每条返回摘要的最大字符数。 |

返回的每条记录含：规范化标识符（DOI/PMID/arXiv）、题目、摘要、作者与期刊（有则给）、年份、URL、融合得分与各库状态 `source_statuses`。`literature_search` 不下载全文、不取引用网络。

### literature_get_fulltext 参数

至少给 `pmcid` / `pmid` / `doi` 之一；`max_chars`（1000–1000000，默认 100000）只截断拼接的 `full_text`，`sections` 与 `abstract` 始终完整返回。无开放获取全文时返回结构化 `status: "not_found"`（这是正常结果，不是错误）；传输或服务失败返回 `status: "error"`。

## 2. 检索策略：每个研究问题至少四个角度

对每个候选声明/假说，至少跑：

1. **机制**：`<通路/分子> AND <疾病/条件> AND (mechanism OR signaling OR pathway)`
2. **方向**：`<通路> AND <条件> AND (upregulation OR activation OR overexpression OR downregulation OR inhibition)`——核对文献方向与你观察到的方向是否一致。
3. **临床/人类证据**：`<通路> AND <疾病> AND (cohort OR clinical OR patient OR GWAS OR eQTL OR survival)`
4. **反证空间（最重要）**：`<通路> AND <疾病> AND (controversy OR inconsistent OR failed OR no association OR refuted)`，以及能解释同一数据的竞争性假说。
5. **关键基因/分子**：对排名前 2–3 的关键基因各查一次：`<gene> AND <disease> AND (function OR role OR mutation OR expression)`。

查询技巧：优先 MeSH 风格术语与同义词（tumour/tumor、colorectal cancer/CRC）；一次查询结果不佳时先换说法，再考虑收窄 `sources` 或放宽年份。

## 3. 限流与部分失败

- 每次搜索后看 `source_statuses`：`ok`（成功有结果）、`empty`（成功无匹配）、`rate_limited`（被限流）、`timeout`、`error`。
- 单库失败不影响整体；可缩小 `sources`、降低 `limit`、稍后重试。
- 建议按需控制频率，不要对同一查询反复轰炸；NCBI 类接口对无 Key 访问有速率限制。

## 4. 证据分级（A–D）

**分级针对「这篇论文对这个具体声明」**，不是论文整体——同一篇论文对一个声明是 A，对另一个声明可能只是 C。

| 等级 | 含义 | 典型来源 |
|---|---|---|
| A | 直接、可复现的因果证据，且在相关体系中验证 | 相关模型中的功能实验（敲除/回补）+ 人类数据 |
| B | 一致的机制或关联证据，未完全因果 | 细胞系/类器官实验、队列关联、eQTL |
| C | 提示性、间接 | 相似疾病中的差异表达、通路数据库、综述 |
| D | 弱、边缘、未复现 | 单个小样本研究、仅有摘要、体系不相干的模型 |

每篇实际使用的论文记录：**PMID/DOI、一句话发现、方向（支持/反对/中立）、等级、模型体系、注意点**，写入研究日志的文献卡。

## 5. 批判性阅读清单（一篇论文成为证据之前）

对任何实质支持或反对假说的论文，核对：

- **模型体系 vs 你的问题**：细胞系 ≠ 病人组织 ≠ 小鼠 ≠ 人类队列，明确写出差距。
- **样本量与设计**：每组 n；效力是否支撑所声称的效应；病例对照还是前瞻。
- **统计**：多重比较是否处理；是否报告效应量而不只是 p<0.05；图表与正文是否一致。
- **混杂**：批次、性别、年龄、用药、组织组成（肿瘤纯度）——论文是否控制了你关心的因素。
- **可复制性**：关键发现是否被独立重复过。一篇论文说“X 激活 Y”只是传闻。
- **引文卫生**：论文引用他人做机制声明时，优先读原文；链式引用会累积错误。

## 6. 反证纪律

- 每个研究问题**必须**至少有一条刻意负向查询（见第 2 节第 4 条）。没搜过反证空间的检索不算完成。
- 找到的反证必须如实记录（方向：反对），哪怕它削弱了用户想支持的假说。隐瞒反证是审查中的 critical 级发现。
- 反证空间搜过且为空时，把“搜了什么查询、结果为空”写进日志——这本身是有信息量的结论。

## 7. 文献卡模板（写入 research-log/<round>/literature.md）

```markdown
## PMID 12345678 / DOI 10.xxxx/xxx — 第一作者等，年份
- **发现**：<一句话>
- **针对**：<哪条声明/假说>，方向：支持 / 反对 / 中立
- **等级**：A | B | C | D
- **模型体系**：<细胞系 / 小鼠 / 人类队列 / …>
- **注意点**：<样本量、混杂、可复制性>
- **原文摘录**（承重句才抄）："<原句>"
```

## 8. 综合为证据链

对每条候选结论，用证据链模板自检：**研究问题 → 检索（记查询与来源状态）→ 论文（PMID/DOI、等级、方向）→ 结论（含反证与残余风险）**。任何一环缺证据即降级为「提示性」或标 `unsupported`。最后按文献综述技能的要求把结论写入研究日志并向用户汇报。
