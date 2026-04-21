> 文档职责：统一记录开发服务器账号授权、SSH 登录放行和免密登录配置的标准流程，作为新增用户与排查登录问题的直接操作手册。
>
> 适用场景：使用 `dev_user` 登录服务器、查看现有用户授权情况、创建 `wangqiao` 账号、验证密码登录、补充 `AllowUsers` 白名单、配置 SSH 公钥免密登录时。
>
> 阅读目标：按固定顺序完成“登录服务器、确认授权现状、创建新用户、验证密码、放行 SSH、配置免密登录”的闭环，不把账号问题、密码问题和 SSH 策略问题混在一起。
>
> 目标读者：项目维护者、运维协作者、需要新增或管理开发服务器账号的后端开发人员。
>
> 维护规范：本文件只保留稳定、可复用、可直接执行的主流程；当服务器地址、账号、`sudo` 策略、`docker` 组、`AllowUsers` 白名单或 SSH 登录方式变化时，必须同步更新；新增内容时优先补充“在哪执行、执行什么、预期输出”，不保留聊天式排障过程和一次性结论。

# 1. 授权模型概览

这台服务器当前采用两类授权方式并存：

- `dev_user`、`xingchen`：通过 `/etc/sudoers.d/<用户名>` 获得 `NOPASSWD: ALL`
- `nickpan`、`frankluo`、`wenny`：通过加入 `sudo` 和 `docker` 组获得权限

如果要新增 `wangqiao`，推荐复制 `nickpan`、`frankluo` 这类模型：

- 创建独立账号
- 加入 `sudo` 组
- 加入 `docker` 组
- 验证密码登录
- 如 SSH 提示不允许登录，再补 `AllowUsers`
- 最后再配置 SSH 公钥免密登录

# 2. 快速闭环

本节只保留最短闭环步骤，适合已经清楚背景、只想快速完成配置时使用。

执行位置分两段：
- 如果你当前还没登录服务器，先在本机执行 `ssh dev_user@47.119.149.179 -p 26333`
- 登录成功后，再执行服务器终端中的服务器侧命令
- 本机终端中的公钥准备、SSH 登录测试和 `ssh -v` 调试，始终在你自己的电脑上执行

注意：
- 下面两段命令不要整段连续粘贴执行
- 本机终端中的公钥准备步骤，必须在你自己的电脑上执行，不是在服务器里执行

服务器终端：

```bash
# 创建 wangqiao 用户，并按提示设置密码
sudo adduser wangqiao

# 加入 sudo 组和 docker 组
sudo usermod -aG sudo wangqiao
sudo usermod -aG docker wangqiao

# 验证用户组与 sudo 规则
id wangqiao
sudo -l -U wangqiao

# 如需排查密码问题，先查看状态，再直接重置
sudo passwd -S wangqiao
sudo passwd wangqiao

# 在服务器本机切换验证密码是否正常
su - wangqiao

# 查找 AllowUsers 配置位置
sudo grep -R -n '^AllowUsers' /etc/ssh/sshd_config /etc/ssh/sshd_config.d 2>/dev/null

# 编辑命中的配置文件，把 wangqiao 追加到 AllowUsers 行尾
sudo vi <实际命中的配置文件>

# 校验并重载 sshd
sudo sshd -t
sudo systemctl reload ssh

# 创建 .ssh 目录并写入 authorized_keys
sudo mkdir -p /home/wangqiao/.ssh

# 打开 authorized_keys，粘贴前面在本机复制的公钥整行内容
sudo vi /home/wangqiao/.ssh/authorized_keys

# 修正目录与文件权限
sudo chown -R wangqiao:wangqiao /home/wangqiao/.ssh
sudo chmod 700 /home/wangqiao/.ssh
sudo chmod 600 /home/wangqiao/.ssh/authorized_keys

# 登录失败时查看最近认证日志
sudo tail -n 80 /var/log/auth.log
```

本机终端：

```bash
# 如果当前还没登录服务器，先用 dev_user 登录
ssh dev_user@47.119.149.179 -p 26333

# 查看现有公钥，优先复用
cat ~/.ssh/id_ed25519.pub

# 如果没有现成公钥，再生成新的 SSH 密钥并查看公钥
ssh-keygen -t ed25519 -C "wangqiao@crazymaplestudio.com"
cat ~/.ssh/id_ed25519.pub

# 测试 wangqiao 的密码登录或免密登录
ssh wangqiao@47.119.149.179 -p 26333

# 登录失败时输出 SSH 详细调试信息
ssh -v wangqiao@47.119.149.179 -p 26333
```

快速判断：
- `id wangqiao` 中应包含 `sudo`、`docker`
- `sudo -l -U wangqiao` 应包含 `(ALL : ALL) ALL`
- `su - wangqiao` 成功表示账号和密码本身正常
- `sudo sshd -t` 无输出表示 sshd 语法通过
- `ssh -v` 配合 `sudo tail -n 80 /var/log/auth.log` 用于判断是密码、公钥还是 `AllowUsers` 问题

# 3. 使用 dev_user 登录服务器

## 3.1 登录入口

- 地址：`47.119.149.179`
- 端口：`26333`
- 管理账号：`dev_user`
- 当前文档默认从 `dev_user` 登录后开始执行

## 3.2 本机登录

执行位置：本机终端。

```bash
# 使用 dev_user 登录开发服务器
ssh dev_user@47.119.149.179 -p 26333
```

预期输出：

```text
dev_user@<hostname>:~$
```

## 3.3 登录后确认

执行位置：服务器终端。

```bash
# 确认当前用户
whoami

# 确认主机名
hostname

# 确认当前账号组信息
id
```

预期输出示例：

```text
dev_user
iZwz97ygdpj5v819fi32x3Z
uid=1000(dev_user) gid=1000(dev_user) groups=1000(dev_user)
```

# 4. 查看现有授权

本节目标是先看清当前服务器怎么授权，再决定新用户按哪类模型添加。

## 4.1 查看用户列表

执行位置：服务器终端。

```bash
# 列出系统用户
getent passwd | cut -d: -f1
```

预期输出：
- 可看到人工账号，如 `dev_user`、`xingchen`、`nickpan`、`frankluo`、`wenchong`、`wenny`
- 也会看到系统账号，如 `root`、`www-data`、`postgres`

## 4.2 查看核心账号组信息

执行位置：服务器终端。

```bash
# 查看当前管理账号
id dev_user

# 查看 sudo + docker 组用户
id nickpan
id frankluo
id wenny

# 查看单独普通账号
id wenchong
id xingchen
```

预期输出判断：
- `nickpan`、`frankluo`、`wenny` 应包含 `sudo`、`docker`
- `dev_user`、`xingchen` 一般只有自己的主组
- `wenchong` 一般只有自己的主组

## 4.3 查看 sudo 授权来源

执行位置：服务器终端。

```bash
# 查看 sudo 组成员
getent group sudo

# 查看当前账号可执行的 sudo 规则
sudo -l

# 查看系统 sudo 主规则
sudo cat /etc/sudoers

# 查看单独账号授权文件
sudo ls -l /etc/sudoers.d
sudo cat /etc/sudoers.d/dev_user
sudo cat /etc/sudoers.d/xingchen
```

预期输出判断：
- `/etc/sudoers` 中应有 `%sudo ALL=(ALL:ALL) ALL`
- `/etc/sudoers.d/dev_user`、`/etc/sudoers.d/xingchen` 中应有 `NOPASSWD: ALL`

## 4.4 当前授权摘要

根据现有结果，当前服务器可按下面理解：

- `dev_user`：独立主组，通过 `sudoers.d` 获得免密 sudo
- `xingchen`：独立主组，通过 `sudoers.d` 获得免密 sudo
- `nickpan`、`frankluo`、`wenny`：各自独立主组，同时在 `sudo`、`docker` 组
- `wenchong`：仅有主组，无额外高权限

# 5. 创建 wangqiao

本节目标是让 `wangqiao` 与 `nickpan`、`frankluo` 保持一致。

执行位置：服务器终端。

```bash
# 1. 创建 wangqiao 用户，并按提示设置登录密码
sudo adduser wangqiao

# 2. 加入 sudo 组，允许执行 sudo 命令
sudo usermod -aG sudo wangqiao

# 3. 加入 docker 组，允许直接执行 docker 命令
sudo usermod -aG docker wangqiao

# 4. 查看用户组信息
id wangqiao

# 5. 查看该用户的 sudo 规则
sudo -l -U wangqiao
```

预期输出示例：

```text
uid=1007(wangqiao) gid=1007(wangqiao) groups=1007(wangqiao),27(sudo),115(docker)
User wangqiao may run the following commands on <hostname>:
    (ALL : ALL) ALL
```

说明：
- 这里不要额外创建 `/etc/sudoers.d/wangqiao`
- 这套做法复制的是“组授权”模型，不是 `dev_user` 的免密 sudo 模型

# 6. 验证 wangqiao 密码登录

先验证账号和密码本身，再验证 SSH。

## 6.1 确认密码状态

执行位置：服务器终端。

```bash
# 查看 wangqiao 的密码状态
sudo passwd -S wangqiao

# 如有需要，直接重置密码
sudo passwd wangqiao
```

预期输出判断：
- 状态正常时通常显示为 `P`
- 如果需要排障，优先先重置一次密码，不要先猜

## 6.2 本机切换验证

执行位置：服务器终端。

```bash
# 使用 wangqiao 的密码切换账号，验证 PAM 是否正常
su - wangqiao
```

预期输出：

```text
wangqiao@<hostname>:~$
```

结果判断：
- `su - wangqiao` 成功：账号与密码正常，后续如果 SSH 失败，优先查 SSH 白名单
- `su - wangqiao` 失败：先回到密码重置，不要先改 SSH

## 6.3 SSH 密码登录验证

执行位置：本机终端。

```bash
# 使用 wangqiao 的密码登录服务器
ssh wangqiao@47.119.149.179 -p 26333
```

预期输出：

```text
wangqiao@47.119.149.179's password:
wangqiao@<hostname>:~$
```

如果这里失败，而第 `5.2` 步成功，优先进入第 6 节检查 `AllowUsers`。

登录失败时，先固定收集下面两段输出，再继续排查：

执行位置：本机终端。

```bash
# 输出 SSH 详细认证过程，便于判断卡在公钥、密码还是策略限制
ssh -v wangqiao@47.119.149.179 -p 26333
```

执行位置：服务器终端。

```bash
# 查看最近认证日志，确认是密码错误、白名单限制还是其他 sshd 拒绝原因
sudo tail -n 80 /var/log/auth.log
```

预期用途：
- 本机 `ssh -v` 输出用于确认 SSH 当前尝试的是 `publickey`、`password` 还是两者同时可用
- 服务器 `auth.log` 用于确认是否出现 `not listed in AllowUsers`、`Failed password`、`invalid user` 等关键日志

# 7. 放行 AllowUsers 白名单

如果日志中出现下面这句，说明问题不是密码，而是 SSH 白名单没有放行：

```text
User wangqiao from <IP> not allowed because not listed in AllowUsers
```

## 7.1 查找配置位置

执行位置：服务器终端。

```bash
# 查找 AllowUsers 写在哪个 sshd 配置文件中
sudo grep -R -n '^AllowUsers' /etc/ssh/sshd_config /etc/ssh/sshd_config.d 2>/dev/null
```

预期输出示例：

```text
/etc/ssh/sshd_config:87:AllowUsers dev_user nickpan frankluo
```

## 7.2 编辑并重载 sshd

执行位置：服务器终端。

```bash
# 编辑命中的配置文件，把 wangqiao 追加到 AllowUsers 行尾
sudo vi <实际命中的配置文件>

# 校验 sshd 配置语法
sudo sshd -t

# 重载 sshd 配置
sudo systemctl reload ssh
```

预期输出判断：
- `sudo sshd -t` 无输出，表示语法通过
- 重载后再次测试 `ssh wangqiao@47.119.149.179 -p 26333`

补充：
- 如果 `reload ssh` 报服务不存在，再试 `sudo systemctl reload sshd`
- 修改期间不要断开当前已成功登录的管理员会话

# 8. 配置 SSH 免密登录

本节目标是让 `wangqiao` 从本机使用 SSH 公钥登录，不再手输服务器密码。

## 8.1 准备本机公钥

执行位置：本机终端。

```bash
# 查看现有 SSH 公钥文件
ls -l ~/.ssh

# 如果已有可复用公钥，直接输出内容
cat ~/.ssh/id_ed25519.pub
```

如果本机还没有可用公钥，再执行：

```bash
# 生成新的 SSH 密钥
ssh-keygen -t ed25519 -C "wangqiao@crazymaplestudio.com"

# 输出公钥内容
cat ~/.ssh/id_ed25519.pub
```

预期输出：
- 复制 `cat` 输出的整行公钥，后续写入服务器 `authorized_keys`

## 8.2 写入 authorized_keys

执行位置：服务器终端，使用 `dev_user` 或其他管理员账号执行。

```bash
# 创建 wangqiao 的 .ssh 目录
sudo mkdir -p /home/wangqiao/.ssh

# 写入授权公钥文件
sudo vi /home/wangqiao/.ssh/authorized_keys

# 修正属主和权限
sudo chown -R wangqiao:wangqiao /home/wangqiao/.ssh
sudo chmod 700 /home/wangqiao/.ssh
sudo chmod 600 /home/wangqiao/.ssh/authorized_keys
```

预期输出判断：

```bash
# 检查目录与文件权限
sudo ls -ld /home/wangqiao/.ssh
sudo ls -l /home/wangqiao/.ssh/authorized_keys
```

预期结果：

```text
drwx------ wangqiao wangqiao /home/wangqiao/.ssh
-rw------- wangqiao wangqiao /home/wangqiao/.ssh/authorized_keys
```

## 8.3 测试免密登录

执行位置：本机终端。

```bash
# 测试 SSH 免密登录
ssh wangqiao@47.119.149.179 -p 26333
```

如失败，再执行：

```bash
# 输出 SSH 详细调试信息
ssh -v wangqiao@47.119.149.179 -p 26333
```

预期输出判断：
- 成功时应直接进入 `wangqiao@<hostname>:~$`
- 如果仍失败，回到第 8 节看日志和白名单

# 9. 常用查询与排查命令

本节只保留高频且有判断价值的命令。

执行位置：服务器终端。

```bash
# 查看某个账号的用户信息与 shell
getent passwd wangqiao

# 查看账号组信息
id wangqiao
groups wangqiao

# 查看 sudo 组成员
getent group sudo

# 查看当前 sudo 规则
sudo -l

# 查看某个用户的 sudo 规则
sudo -l -U wangqiao

# 查看 sshd 白名单配置位置
sudo grep -R -n '^AllowUsers' /etc/ssh/sshd_config /etc/ssh/sshd_config.d 2>/dev/null

# 查看认证日志
sudo tail -n 80 /var/log/auth.log
```

高频判断：
- `su - wangqiao` 成功但 SSH 失败：优先看 `AllowUsers`
- `id wangqiao` 包含 `sudo`、`docker`：说明授权模型已复制成功
- `docker` 命令通常不需要 `sudo`
- 系统管理命令通常仍需要 `sudo`

# 10. 操作边界

- 不要未经确认就新增 `/etc/sudoers.d/wangqiao`
- 不要直接用普通编辑器修改 `/etc/sudoers`，优先使用 `visudo`
- 不要把“SSH 登录失败”一律归因为密码错误，先区分账号、密码、`AllowUsers`、公钥权限
- 不要在修改 `sshd` 白名单期间断开当前管理员会话
- 不要把 `docker` 组当成普通权限组，它本身就是高权限
