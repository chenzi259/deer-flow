# 我的修改记录（changelog_myself）

本文件记录本 fork（`chenzi259/deer-flow`）相对于原始仓库（`bytedance/deer-flow`）所做的全部自定义修改，最新的修改写在最上面。

同步上游代码时如遇冲突，可参照此处确认哪些文件是自己改过的、应保留哪一方。

---

## 2026-11-18

### 1. 将 logo 替换为"警"字 logo

**修改文件：**

| 文件 | 用途 | 修改内容 |
| --- | --- | --- |
| `frontend/public/favicon.ico` | 浏览器标签页图标 | 替换为红底（`#D7261E`）圆角方块 + 白色"警"字，内含 16/32/48/64 四种尺寸 |
| `frontend/public/images/deer.svg` | 首页、登录页、初始化页的大幅背景剪影（以 CSS mask 方式使用） | 原鹿形剪影替换为实心"警"字剪影，画布 2048×2048 |

**说明：**

- "警"字字形取自 Noto Sans CJK SC Black（SIL OFL 许可），已转换为矢量路径，不依赖浏览器字体。
- 保留了 `deer.svg` 文件名，因此无需修改引用它的代码（`src/app/(auth)/login/page.tsx`、`src/app/(auth)/setup/page.tsx`、`src/components/landing/hero.tsx`），减少与上游的冲突。
- 未改动 `deploy/helm/deer-flow/Chart.yaml` 中的 `icon`，它指向上游仓库的图片地址。

**同步上游时：** 若上游修改了这两个文件导致冲突，保留自己的版本即可：

```bash
git checkout --ours frontend/public/favicon.ico frontend/public/images/deer.svg
git add frontend/public/favicon.ico frontend/public/images/deer.svg
```

### 0. 新增上游同步脚本

- 新增 `scripts/sync-upstream.sh`：拉取 `bytedance/deer-flow` 最新代码并合并到当前分支，支持 `--dry-run`、`--push`、`--stash`、`--rebase`。
