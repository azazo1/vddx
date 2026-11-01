# 显示可用 recipe.
[private]
default:
    @just --list

# 编译调试版本, 不产出应用包.
build:
    swift build --disable-sandbox

# 组装可运行的调试版应用包到 target/VDDX.app.
app:
    uv run --no-project python scripts/package.py --configuration debug --output target/VDDX.app --version-display dev-build --version-short 0.0.0 --channel dev --form dev

# 以隔离数据目录启动调试实例, 完整日志写入 target/vddx-debug.
debug: app
    env VDDX_DATA_DIR=target/vddx-debug/data VDDX_LOG_DIR=target/vddx-debug/logs VDDX_LOG_LEVEL=trace VDDX_LOG_STDERR=1 target/VDDX.app/Contents/MacOS/VDDX

# 打开调试版应用包 (不经终端).
run: app
    open target/VDDX.app

# 生成当前平台的安装版 dmg.
dist:
    uv run --no-project python scripts/dist.py

# 生成 v0.0.0 的 fake 安装版, 用于验证更新流程.
fake-dist:
    VDDX_FAKE=1 uv run --no-project python scripts/dist.py

# 清理构建缓存与产物.
clean:
    swift package clean
    rm -rf target dist .build
