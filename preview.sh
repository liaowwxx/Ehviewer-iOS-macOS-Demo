#!/bin/bash
# ============================================================
# EhViewer docs 本地预览：一键生成预览文件并启动本地服务器
#
# 用法:
#   ./preview.sh            # 生成预览文件并启动服务器（默认端口 8123）
#   ./preview.sh open       # 启动服务器并自动打开浏览器
#   ./preview.sh stop       # 停止预览服务器
#   ./preview.sh restart    # 停止后重新启动
#   PORT=9000 ./preview.sh  # 自定义端口
#
# 预览目录: _preview/  （已加入 .gitignore，不会提交）
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREVIEW_DIR="$SCRIPT_DIR/_preview"
PORT="${PORT:-8123}"
URL_BASE="http://127.0.0.1:$PORT/Ehviewer-iOS-macOS-Demo"
LOG_FILE="$SCRIPT_DIR/_preview-server.log"

cd "$SCRIPT_DIR"

usage() {
  sed -n '2,12p' "$0" | sed 's/^# {0,1}//'
  exit 1
}

server_pid() {
  lsof -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null | head -1 || true
}

stop_server() {
  local pid
  pid="$(server_pid)"
  if [ -n "$pid" ]; then
    kill "$pid" 2>/dev/null || true
    for _ in 1 2 3 4 5; do
      [ -z "$(server_pid)" ] && break
      sleep 0.3
    done
    echo "✓ 已停止预览服务器 (PID $pid, 端口 $PORT)"
  else
    echo "预览服务器未在运行"
  fi
  rm -f "$LOG_FILE"
}

generate() {
  echo "▶ 生成预览文件 ..."
  if ! command -v node >/dev/null 2>&1; then
    echo "✗ 未找到 node，无法生成预览文件" >&2
    exit 1
  fi
  node "$SCRIPT_DIR/scripts/render-preview.mjs"
}

start_server() {
  if [ -n "$(server_pid)" ]; then
    echo "端口 $PORT 已被占用，先停止旧服务 ..."
    stop_server
  fi

  generate

  if ! command -v python3 >/dev/null 2>&1; then
    echo "✗ 未找到 python3，无法启动服务器" >&2
    exit 1
  fi

  echo "▶ 启动服务器 (端口 $PORT) ..."
  cd "$PREVIEW_DIR"
  nohup python3 -m http.server "$PORT" >"$LOG_FILE" 2>&1 &
  sleep 1

  if [ -z "$(server_pid)" ]; then
    echo "✗ 服务器启动失败，日志见 $LOG_FILE" >&2
    exit 1
  fi

  local code
  code="$(curl -s -o /dev/null -w "%{http_code}" "$URL_BASE/" || true)"
  if [ "$code" = "200" ]; then
    echo ""
    echo "======================================================"
    echo "  预览已就绪:  $URL_BASE/"
    echo "  英文首页:    $URL_BASE/en/"
    echo "  使用说明:    $URL_BASE/guide/"
    echo "  停止服务:    ./preview.sh stop"
    echo "======================================================"
  else
    echo "✗ 服务器已启动但首页返回 HTTP $code，请检查 $LOG_FILE" >&2
    exit 1
  fi
}

case "${1:-}" in
  ""|start)
    start_server
    ;;
  open)
    start_server
    open "$URL_BASE/"
    ;;
  stop)
    stop_server
    ;;
  restart)
    stop_server
    start_server
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "未知参数: $1" >&2
    usage
    ;;
esac
