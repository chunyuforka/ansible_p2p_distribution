# Ansible-based P2P File Distribution Tool

[中文文档](#中文文档)

This project implements a P2P file distribution tool using Ansible. It relies on the `rsync` and `nc` commands and has been tested on Ubuntu. The tool automatically computes sender-to-target mappings based on a tree structure and executes parallel transfers, ensuring efficient and reliable distribution of files or directories across multiple nodes.

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Requirements](#requirements)
- [Usage](#usage)
- [File Structure](#file-structure)
- [Contribution](#contribution)
- [License](#license)
- [中文文档](#中文文档)

---

## Overview

This tool employs a peer-to-peer architecture to efficiently distribute files or directories by forwarding data between a control node (file sender) and downstream nodes. While the control node directly initiates the transfer, the receiver nodes run an rsync daemon to ensure that the upstream transmission is complete before proceeding.

---

## Features

- **Automatic Sender Mapping:** Constructs a complete tree model based on the full inventory and a defined branching factor to automatically compute downstream targets.
- **Reliable Data Transfer:** Uses an rsync daemon for transferring data and lock files, ensuring two consecutive successful transfers before confirming completion.
- **Parallel Distribution:** Supports parallel forwarding to multiple downstream nodes to improve overall efficiency.
- **Flexible Parameters:** Customizable source and destination paths as well as rsync port settings to meet various environment requirements.

---

## Requirements

- **Operating System:** Ubuntu (tested)
- **Dependencies:**  
  - Ansible  
  - rsync  
  - netcat (nc)  
  - Bash

---

## Usage

### Parameter Description

- **fork:** The branching factor, specifying how many downstream nodes each sender node should forward to (e.g., 2 or 3).
- **src_path:** Path of the file or directory to be transferred from the control node.
- **dest_path:** Target path where each node will store the received file or directory.
- **rsync_port:** (Optional) The rsync listening port, default is 873.
- **global_inventory:** (Automatically calculated) Full list of node IPs.
- **local_ip:** (Automatically calculated) Current node IP.

### Execution Example

1. **Using an inventory file:**

   ```bash
   ansible-playbook -i hosts p2p.yaml -f 32
   ```

2. **Injecting parameters directly into the inventory:**

   ```bash
   ansible-playbook -i 192.168.1.1,192.168.1.2 p2p.yaml -f 32
   ```

---

## 中文文档

[English Documentation](#ansible-based-p2p-file-distribution-tool)

本项目实现了一套基于 Ansible 的 P2P 文件分发方案，依赖于 `rsync` 和 `nc` 命令，在 Ubuntu 环境下已进行过测试。该工具通过自动生成发送映射和多级并行传输，实现了高效、可靠的文件（或目录）分发，适用于大规模节点间的数据同步与更新。

---

## 目录

- [概述](#概述)
- [特性](#特性)
- [环境要求](#环境要求)
- [使用方法](#使用方法)
- [文件结构](#文件结构)
- [贡献](#贡献)
- [许可证](#许可证)

---

## 概述

本工具基于 P2P 架构，通过控制机与下游节点间的数据转发，实现文件或目录的高效分发。控制机（文件发送源）无需启动 rsync 监听，而下游节点则通过 rsync 守护进程进行数据和锁文件的接收，确保上游传输完成后再进行下一步操作。

---

## 特性

- **自动发送映射：** 根据全量节点清单和设定的裂变值，构造完全树模型，自动计算每个节点的下游目标。
- **可靠的数据传输：** 利用 rsync 守护进程实现数据和锁文件的传输，要求数据传输连续成功两次后才确认完成。
- **并行分发：** 支持多个下游节点的并行转发，提升整体传输效率。
- **灵活的参数设置：** 支持自定义源路径、目标路径、rsync 监听端口等参数，满足不同环境下的需求。

---

## 环境要求

- **操作系统：** Ubuntu（已测试）
- **依赖软件：**  
  - Ansible  
  - rsync  
  - netcat (nc)  
  - Bash

---

## 使用方法

### 参数说明

- **fork：** 裂变值，每个发送节点向下转发的目标数量（如 2 或 3）。
- **src_path：** 控制机上的待传输文件或目录路径。
- **dest_path：** 各节点接收数据后存放文件或目录的目标路径。
- **rsync_port：** （可选）rsync 监听端口，默认为 873（或根据实际需求配置）。
- **global_inventory：** (自动计算)全量节点 IP。
- **local_ip：** （自动计算）当前节点 IP。

### 运行示例

1. **使用主机清单：**

   ```bash
   ansible-playbook -i hosts p2p.yaml -f 32
   ```

2. **参数注入主机清单：**

   ```bash
   ansible-playbook -i 192.168.1.1,192.168.1.2 p2p.yaml -f 32
   ```
