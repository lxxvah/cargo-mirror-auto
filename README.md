\# cargo-mirror-auto



> 自动选择最快的 Cargo 镜像 · Auto-select the fastest Cargo mirror for faster crate downloads.



\[!\[Platform](https://img.shields.io/badge/platform-Windows-blue)](https://github.com/lxxvah/cargo-mirror-auto)

\[!\[PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue)](https://github.com/lxxvah/cargo-mirror-auto)

\[!\[License](https://img.shields.io/badge/license-MIT-green)](LICENSE)



\## 简介



一套 PowerShell 脚本，自动完成：



\- 测试所有国内 Cargo 镜像（TCP:443 连通性）

\- 自动选最快的镜像

\- 写入 `\\\~/.cargo/config.toml`

\- 每次执行 `cargo` 时自动检查镜像新鲜度（默认 1 小时）



\*\*效果\*\*：`cargo build`、`cargo install`、`cargo add` 都走最快镜像，无需手动切换。



\## 支持的镜像



| Key | 镜像名 |

|-----|--------|

| `tuna` | 清华大学 TUNA |

| `ustc` | 中国科学技术大学 |

| `aliyun` | 阿里云 |

| `rsproxy` | rsproxy.cn（字节跳动） |

| `sjtu` | 上海交通大学 |

| `nju` | 南京大学 |

| `official` | 官方源 crates.io |



\## 快速开始



```powershell

\\# 1. 下载脚本

git clone https://github.com/lxxvah/cargo-mirror-auto.git

cd cargo-mirror-auto



\\# 2. 复制到脚本目录

New-Item -ItemType Directory -Path "E:\\\\code\\\\scripts" -Force

Copy-Item \\\*.ps1 "E:\\\\code\\\\scripts\\\\" -Force



\\# 3. 运行安装

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

E:\\\\code\\\\scripts\\\\install-cargo-auto.ps1


