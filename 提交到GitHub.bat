@echo off
chcp 65001 >nul
cd /d "%~dp0"

echo ==========================================================
echo    提交 mmusic-client 到 GitHub
echo ==========================================================
echo.

git rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 goto :notrepo

rem --- 清理残留的 index.lock,否则所有 git 写操作都会失败 ---
if not exist ".git\index.lock" goto :nolock
echo [提示] 发现残留的 index.lock,已自动移除
del /f /q ".git\index.lock" >nul 2>&1
echo.
:nolock

rem --- 先把远端的新提交拉下来,避免推送被拒 ---
echo --- 检查远端 ---
git fetch origin >nul 2>&1
set "BEHIND="
for /f %%i in ('git rev-list --count HEAD..@{u} 2^>nul') do set "BEHIND=%%i"
if "%BEHIND%"=="" goto :nopull
if "%BEHIND%"=="0" goto :nopull
echo [提示] 远端有 %BEHIND% 个新提交,正在合并...
git pull --rebase origin HEAD
if errorlevel 1 goto :pullfail
:nopull
echo.

echo --- 当前改动 ---
git -c core.quotepath=false status --short
echo.

set "CHANGES="
for /f %%i in ('git status --porcelain ^| find /c /v ""') do set "CHANGES=%%i"
if "%CHANGES%"=="0" goto :nochange

set "MSG="
set /p MSG=请输入提交说明[直接回车则用 Update]:
if "%MSG%"=="" set "MSG=Update"
echo.

git add -A

echo --- 即将提交以下内容 ---
git -c core.quotepath=false diff --cached --stat
echo.
set "YN="
set /p YN=确认提交? [Y/N]:
if /i not "%YN%"=="Y" goto :cancel
echo.

git commit -m "%MSG%"
if errorlevel 1 goto :commitfail
echo.
goto :dopush


rem ==========================================================
rem  工作区没有改动:检查是否还有没推送的提交
rem ==========================================================
:nochange
echo 工作区没有需要提交的改动。
echo.
set "AHEAD="
for /f %%i in ('git rev-list --count @{u}..HEAD 2^>nul') do set "AHEAD=%%i"
if "%AHEAD%"=="" goto :noupstream
if "%AHEAD%"=="0" goto :uptodate

echo [提示] 但本地还有 %AHEAD% 个提交没有推送到 GitHub:
echo.
git --no-pager log --oneline @{u}..HEAD
echo.
set "YN="
set /p YN=是否现在推送这些提交? [Y/N]:
if /i not "%YN%"=="Y" goto :cancel
echo.
goto :dopush


rem ==========================================================
rem  推送
rem ==========================================================
:dopush
echo --- 正在推送到 GitHub ---
git push origin HEAD
if errorlevel 1 goto :pushfail

echo.
echo ==========================================================
echo    完成
echo ==========================================================
echo.
git -c core.quotepath=false status -sb
echo.
echo push 到 main 会自动触发 APK 构建,约 10 分钟。
echo iOS 不会自动构建,需手动触发:
echo    Actions 页面 -^> 左侧选 Build iOS unsigned ipa -^> Run workflow
echo.
echo 查看构建进度:
echo    https://github.com/chenweitian423/mmusic-client/actions
echo.
pause
exit /b 0


rem ==========================================================
rem  各种退出分支
rem ==========================================================
:uptodate
echo 本地与 GitHub 完全同步,无需推送。
echo.
pause
exit /b 0

:noupstream
echo [警告] 当前分支没有设置上游分支,无法判断是否需要推送。
echo        可执行: git push -u origin HEAD
echo.
pause
exit /b 1

:notrepo
echo [错误] 当前目录不是 git 仓库。
echo        请把本脚本放在 mmusic-client 文件夹里再运行。
echo.
pause
exit /b 1

:cancel
echo 已取消,没有任何东西被推送。
echo.
pause
exit /b 0

:pullfail
echo.
echo [错误] 拉取远端提交失败,可能有冲突,需要手动处理。
echo.
pause
exit /b 1

:commitfail
echo.
echo [错误] 提交失败。若提示缺少用户名/邮箱,先执行:
echo    git config --global user.name  "zihen423"
echo    git config --global user.email "zihen423@gmail.com"
echo.
pause
exit /b 1

:pushfail
echo.
echo [错误] 推送失败。常见原因:
echo    1. 网络问题       - 重试即可
echo    2. 凭据过期       - 会弹窗要求重新登录 GitHub,登录后重试
echo    3. 远端有新提交   - 重新运行本脚本,开头会自动拉取
echo.
echo 注意:提交已经保存在本地,不会丢失,修好后重跑即可推送。
echo.
pause
exit /b 1
