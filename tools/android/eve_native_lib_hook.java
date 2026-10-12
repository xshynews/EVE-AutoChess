	// [eve-patch] 把「APK 原生库目录 + 联机内核状态」落盘给 GDScript。
	//
	// 为什么必须从 Java 侧拿（2026-10-12 联网专项审查 N01 + 引擎源码核对）：
	//   ① `ApplicationInfo.nativeLibraryDir` 是安卓上**唯一允许 exec 的位置**
	//      （Android 10+ 禁止在应用数据目录 exec）；
	//   ② Godot（含 4.7 的 Kotlin 实现）**完全没有暴露**它；
	//   ③ 想从 `/proc/self/maps` 反推也不行 —— 绝对路径的 FileAccess 后端是 Java 实现
	//      （`FileAccessFilesystemJAndroid`），而 `StorageScope` 对 `/proc/...` 与
	//      `/data/app/.../lib/...` 一律返回 UNKNOWN ⇒ 被拒。
	//   本方法写进 `getFilesDir()`，那正是 GDScript 的 `user://`，读得动。
	//
	// ⛔ 删掉本方法 = 安卓联机退回「找不到内核」。
	//    本文件由 `tools/pipeline/_android_patch.py` 注入到构建模板的 GodotApp.java
	//    （模板重装后重跑该脚本即可，幂等）。
	private void eveWriteNativeLibInfo() {
		try {
			java.io.File dir = new java.io.File(getApplicationInfo().nativeLibraryDir);
			java.io.File core = new java.io.File(dir, "libetcore.so");
			StringBuilder sb = new StringBuilder();
			sb.append("native_lib_dir=").append(dir.getAbsolutePath()).append('\n');
			sb.append("core_exists=").append(core.exists() ? "true" : "false").append('\n');
			sb.append("core_can_execute=").append(core.canExecute() ? "true" : "false").append('\n');
			sb.append("core_size=").append(core.length()).append('\n');
			sb.append("sdk_int=").append(android.os.Build.VERSION.SDK_INT).append('\n');
			java.io.File out = new java.io.File(getFilesDir(), "eve_native_lib_dir.txt");
			java.io.FileOutputStream fos = new java.io.FileOutputStream(out);
			try {
				fos.write(sb.toString().getBytes("UTF-8"));
			} finally {
				fos.close();
			}
			Log.i("EVE", "[eve] native lib info: " + sb.toString().replace('\n', ' '));
			Log.i("EVE", "[eve] user dir: " + getFilesDir().getAbsolutePath());
		} catch (Throwable t) {
			Log.e("EVE", "[eve] write native lib info failed", t);
		}
	}

	// [eve-patch] 独立自检：起一次内核的 `--version`，结果落盘 + 打日志。
	//
	// 目的：把「**系统禁止 exec**」与「内核起来了但组网失败」彻底分开 —— 否则玩家/我们
	// 只能看到一句「内核没起来」，无法判断是机型限制还是网络问题。
	// 跑在后台线程里（调用点在 onCreate），⛔ 绝不阻塞启动。
	private void eveProbeExec() {
		String msg;
		try {
			java.io.File core = new java.io.File(getApplicationInfo().nativeLibraryDir, "libetcore.so");
			java.lang.ProcessBuilder pb = new java.lang.ProcessBuilder(core.getAbsolutePath(), "--version");
			pb.redirectErrorStream(true);
			java.lang.Process pr = pb.start();
			java.io.BufferedReader r = new java.io.BufferedReader(
					new java.io.InputStreamReader(pr.getInputStream()));
			StringBuilder out = new StringBuilder();
			String line;
			while ((line = r.readLine()) != null) {
				if (out.length() < 160) {
					out.append(line).append(' ');
				}
			}
			msg = "ok out=" + out.toString().trim();
		} catch (Throwable t) {
			msg = "fail " + t.getClass().getSimpleName() + ": " + t.getMessage();
		}
		Log.i("EVE", "[eve] exec probe -> " + msg);
		try {
			java.io.FileOutputStream fos = new java.io.FileOutputStream(
					new java.io.File(getFilesDir(), "eve_exec_probe.txt"));
			try {
				fos.write(msg.getBytes("UTF-8"));
			} finally {
				fos.close();
			}
		} catch (Throwable t) {
			Log.e("EVE", "[eve] write exec probe failed", t);
		}
	}
