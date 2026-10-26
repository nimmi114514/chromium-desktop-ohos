/*
 * Copyright (c) 2023-2026 Huawei Device Co., Ltd.
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 * this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 * this list of conditions and the following disclaimer in the documentation
 * and/or other materials provided with the distribution.
 *
 * 3. Neither the name of the copyright holder nor the names of its contributors
 * may be used to endorse or promote products derived from this software without
 * specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
 * OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
 * OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 * ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
import LogUtil from "./LogUtil";
import { deviceInfo } from '@kit.BasicServicesKit';
import { NativeContext } from "../interface/CommonInterface";
import JsBindingUtils from "./JsBindingUtils";
import { ContextType } from "../common/Constants";
import fs from '@ohos.file.fs';

const TAG = 'CmdArgsHelper';
const SDK_VERSION_19 = 19;
const ENABLE_USER_INPUT_ARGS = false;
// Keep 2-in-1 devices on desktop sites instead of the mobile variant.
// Community Google credentials so sign-in/sync and Google services work
// (public values used by Arch/Gentoo/Slackware Chromium builds).
const GOOGLE_API_KEY = 'AIzaSyBHDrl33hwRp4rMQY0ziRbj8K9LPA6vUCY';
const GOOGLE_OAUTH_CLIENT_ID = '77185425430.apps.googleusercontent.com';
const GOOGLE_OAUTH_CLIENT_SECRET = 'OTJgUOQcT7lO7GsGZq2G4IlT';
const DESKTOP_USER_AGENT =
  'Mozilla/5.0 (X11; Linux aarch64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/158.0.0.0 Safari/537.36';

export interface ParsedArg {
  name: string;
  value: string | null; // null 表示纯 flag，无值
}

export class CmdArgsHelper {
  private static readonly DEFAULT_ARGS: string[] = [
    // The original132 BasicLoader supplies argv[0] in GetEntryArgs().
    "--use-gl=egl",
    "--enable-features=UseOzonePlatform",
    "--ozone-platform=ohos",
    "--enable-logging",
    "--ohos-enable-hdr",
    "--no-zygote",
    "--disable-gpu-watchdog",
    "--ohos-refresh-rate=144",
    `--user-agent=${DESKTOP_USER_AGENT}`,
  ];
  private static readonly BLOCKED_ARGS_NAME: Set<string> = new Set([
    'ozone-platform',
    'bundle-installation-dir'
  ]);
  private static readonly CAN_BE_REPLACED_ARGS: string[] = [
    "--ozone-dump-file=/data/storage/el2/base/cache/",
    "--user-data-dir=/data/storage/el2/base/files/",
    "--force-renderer-accessibility=complete",
  ];

  private static getNativeContext(): NativeContext {
    return JsBindingUtils.getNativeContext(ContextType.kMainProcess);
  }

  private static prepareGoogleConfig(): string | null {
    // The Chromium 132 Gaia configuration reader supplies default credentials
    // to every client. The OAuth command-line switches configure CLIENT_MAIN
    // alone, while HasOAuthClientConfigured also checks the remoting clients.
    const path = getContext().filesDir + '/chromium-google-services.json';
    const apiKeys: Record<string, string> = {
      'GOOGLE_API_KEY': GOOGLE_API_KEY,
      'GOOGLE_DEFAULT_CLIENT_ID': GOOGLE_OAUTH_CLIENT_ID,
      'GOOGLE_DEFAULT_CLIENT_SECRET': GOOGLE_OAUTH_CLIENT_SECRET,
    };
    try {
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, JSON.stringify({ api_keys: apiKeys }));
      } finally {
        fs.closeSync(file);
      }
      return path;
    } catch (err) {
      LogUtil.error(TAG, 'Unable to prepare Google service configuration');
      return null;
    }
  }

  public static buildArgs(startUri: string, userInputArgs?: string[], appId?: string): string[] {
    // 添加默认参数
    // Copy the defaults so each window gets an independent argument list.
    let vec_args = [...CmdArgsHelper.DEFAULT_ARGS];

    // pad添加 --in-process-gpu
    if (deviceInfo.deviceType === 'tablet') {
      vec_args.push("--in-process-gpu");
    }

    // 获取devConfig参数并整合
    const nativeContext = CmdArgsHelper.getNativeContext();
    if (typeof nativeContext.GetDevCommandLines === 'function') {
      try {
        vec_args = vec_args.concat(nativeContext.GetDevCommandLines());
      } catch (err) {
        LogUtil.warn(TAG, 'GetDevCommandLines unavailable; using built-in arguments');
      }
    }

    let resDir = '--bundle-installation-dir=' + getContext().resourceDir;
    vec_args.push(resDir);
    const googleConfig = CmdArgsHelper.prepareGoogleConfig();
    if (googleConfig) {
      vec_args.push('--gaia-config=' + googleConfig);
    }
    vec_args.push(startUri);
    if (appId !== undefined) {
      vec_args.push(appId);
    }

    let jsFlagsValue: string | null = null;
    // 接收用户输入的参数可能有安全问题，默认强制关闭，三方应用如有需要，开发者自行开启
    if (ENABLE_USER_INPUT_ARGS && userInputArgs && userInputArgs.length !== 0) {
      let cmdArgs: string[] = [];
      let parsedUserInputArgs = CmdArgsHelper.parseArgs(userInputArgs);

      // js-flags特殊处理
      jsFlagsValue = CmdArgsHelper.buildJsFlags(parsedUserInputArgs);
      const jsFlagsIndex = parsedUserInputArgs.findIndex(arg => arg.name === 'js-flags');
      if (jsFlagsIndex >= 0) {
        parsedUserInputArgs[jsFlagsIndex].value = jsFlagsValue;
      } else if (jsFlagsValue) {
        parsedUserInputArgs.push({ name: 'js-flags', value: jsFlagsValue });
      }

      cmdArgs = CmdArgsHelper.filterBlockedArgs(parsedUserInputArgs);
      vec_args = vec_args.concat(cmdArgs);
    } else {
      jsFlagsValue = CmdArgsHelper.buildJsFlags();
      if (jsFlagsValue) {
        vec_args.push(CmdArgsHelper.stringifyOne({ name: 'js-flags', value: jsFlagsValue }));
      }
    }

    // 检查 vec_args 中是否包含 CAN_BE_REPLACED_ARGS 中的参数
    const parsedVecArgs = CmdArgsHelper.parseArgs(vec_args);
    const vecArgNames = new Set(parsedVecArgs.map(arg => arg.name));

    // 如果 vec_args 中不包含 CAN_BE_REPLACED_ARGS 中的参数，则追加
    for (const arg of CmdArgsHelper.CAN_BE_REPLACED_ARGS) {
      const parsedArg = CmdArgsHelper.parseOne(arg);
      if (parsedArg && !vecArgNames.has(parsedArg.name)) {
        vec_args.push(arg);
      }
    }

    return vec_args;
  }

  public static buildJsFlags(parsedUserInputArgs?: ParsedArg[]): string | null {
    const deviceType = deviceInfo.deviceType;
    const sdkVersion = deviceInfo.sdkApiVersion;
    const isTablet = (deviceType === 'tablet');
    const needJitlessForTablet = isTablet && (sdkVersion < SDK_VERSION_19);

    // 安全模式+权限判断需要jitless
    // Older adapter libraries do not export this optional capability.
    let securityJitless = false;
    const nativeContext = CmdArgsHelper.getNativeContext();
    if (typeof nativeContext.ShouldDisableJit === 'function') {
      try {
        securityJitless = nativeContext.ShouldDisableJit();
      } catch (err) {
        LogUtil.warn(TAG, 'ShouldDisableJit unavailable; keeping JIT enabled');
      }
    }

    // 合并系统需求(平板+安全模式)
    let systemJsFlags: string | null = null;
    if (needJitlessForTablet || securityJitless) {
      systemJsFlags = '--jitless';
    }

    // 从用户输入中解析js-flags
    let userJsFlagsValue: string | null = null;
    if (parsedUserInputArgs) {
      for (const parsed of parsedUserInputArgs) {
        if (parsed.name === 'js-flags') {
          userJsFlagsValue = parsed.value;
          break;
        }
      }
    }

    return CmdArgsHelper.mergeJsFlags(systemJsFlags, userJsFlagsValue);
  }

  private static mergeJsFlags(systemJsFlags: string | null, userJsFlagsValue: string | null): string | null {
    // 情况1: 系统不需要jitless，用户也没输入
    if (!systemJsFlags && !userJsFlagsValue) {
      return null;
    }

    // 情况2: 系统需要jitless，用户没输入
    if (systemJsFlags && !userJsFlagsValue) {
      return systemJsFlags;
    }

    // 情况3: 系统不需要jitless，用户输入了
    if (!systemJsFlags && userJsFlagsValue) {
      return userJsFlagsValue;
    }

    // 情况4: 系统需要jitless，用户也输入了
    // 检查用户输入是否已包含--jitless
    if (userJsFlagsValue && userJsFlagsValue.includes('--jitless')) {
      return userJsFlagsValue;
    } else {
      // 用户没输入jitless，系统需要，添加到最前面
      return systemJsFlags + ' ' + userJsFlagsValue;
    }
  }

  public static getCmdArgs(args: Object | undefined): string[] {
    try {
      if (args === undefined) {
        return [];
      }
      if (typeof args === 'string' && args.length > 0) {
        LogUtil.warn(TAG, "cmdArgs str:" + args);
        return CmdArgsHelper.tokenize(args);
      } else if (Array.isArray(args) && args.length > 0) {
        return args;
      }
      return [];
    } catch (err) {
      LogUtil.error(TAG, `get cmdArgs array failed, args is: ${args}, error:${JSON.stringify(err)}`);
      return [];
    }
  }

  /**
   * 把命令行字符串解析成 argv 数组，模拟 shell tokenize 行为
   * 支持双引号"..."包裹含空格的值，支持转义符\"
   *
   * 示例：
   * "--js-flags=\"--jitless --opt\" --nosandbox"
   * → ["--js-flags=--jitless --opt", "--no-sandbox"]
   */
  static tokenize(input: string): string[] {
    const args: string[] = [];
    let current = '';
    let inDoubleQuote = false;

    for (let i = 0; i < input.length; i++) {
      const ch = input[i];

      // 处理转义符
      if (ch === '\\' && i + 1 < input.length) {
        const next = input[i + 1];
        if (next === '"' || next === '\\') {
          current += next;
          i++; // 跳过下一个字符
          continue;
        }
      }

      // 处理双引号
      if (ch === '"') {
        inDoubleQuote = !inDoubleQuote;
        continue;
      }

      // 空格分割（仅在引号外）
      if (ch === ' ' && !inDoubleQuote) {
        if (current.length > 0) {
          args.push(current);
          current = '';
        }
        continue;
      }

      current += ch;
    }

    if (inDoubleQuote) {
      LogUtil.error(TAG, `tokenize failed: unclosed double quote in: "${input}"`);
      return [];
    }

    if (current.length > 0) {
      args.push(current);
    }

    return args;
  }


  static filterBlockedArgs(args: ParsedArg[]): string[] {
    const result: string[] = [];
    for (const arg of args) {
      if (!CmdArgsHelper.BLOCKED_ARGS_NAME.has(arg.name)) {
        result.push(CmdArgsHelper.stringifyOne(arg));
      } else {
        LogUtil.warn(TAG, `${arg} is blocked!`);
      }
    }
    return result;
  }

  static parseArgs(args: string[]): ParsedArg[] {
    const result: ParsedArg[] = [];
    for (const arg of args) {
      const parsedArg = CmdArgsHelper.parseOne(arg);
      if (parsedArg !== null) {
        result.push(parsedArg);
      }
    }
    return result;
  }

  static parseOne(arg: string): ParsedArg | null {
    const trimmed = arg.trim();

    let body: string;
    if (trimmed.startsWith('--')) {
      body = trimmed.slice(2);
    } else if (trimmed.startsWith('-')) {
      body = trimmed.slice(1);
    } else {
      return null;
    }

    if (body.length === 0) {
      return null;
    } // 单独的 "--" 或 "-"
    if (body.startsWith('-')) {
      return null;
    } // "---abc" 不合法，Chromium 也不认

    const eqIndex = body.indexOf('=');
    if (eqIndex === 0) {
      return null;
    } // "--=value" 或 "-=value" 不合法

    if (eqIndex < 0) {
      return { name: body, value: null };
    }
    return {
      name: body.slice(0, eqIndex),
      value: body.slice(eqIndex + 1),
    };
  }

  static stringifyOne(parsedArg: ParsedArg): string {
    return parsedArg.value !== null ? `--${parsedArg.name}=${parsedArg.value}` : `--${parsedArg.name}`;
  }

  static stringify(parsedArgs: ParsedArg[]): string[] {
    return parsedArgs.map(arg => CmdArgsHelper.stringifyOne(arg));
  }

  static preProcessArgs(vecArgs: string[]): string[] {
    // 处理参数，暂时没有具体实现
    return vecArgs;
  }
}
