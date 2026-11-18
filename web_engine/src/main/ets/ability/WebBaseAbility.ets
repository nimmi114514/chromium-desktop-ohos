/*
 * Copyright (c) 2023-2025 Haitai FangYuan Co., Ltd.
 * Redistribution and use in source and binary forms, with or without modification,
 * are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice, this list of
 *    conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice, this list
 *    of conditions and the following disclaimer in the documentation and/or other materials
 *    provided with the distribution.
 *
 * 3. Neither the name of the copyright holder nor the names of its contributors may be used
 *    to endorse or promote products derived from this software without specific prior written
 *    permission.
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

import UIAbility from '@ohos.app.ability.UIAbility';
import LogUtil from '../utils/LogUtil';
import window from '@ohos.window';
import Want from '@ohos.app.ability.Want';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import JsBindingUtils from '../utils/JsBindingUtils';
import { ChangeEventType, NativeContext, WindowStatus } from '../interface/CommonInterface';
import { CommandType, ConfigData, ContextType } from '../common/Constants';
import CheckEmptyUtils from '../utils/CheckEmptyUtils';
import { WebProxy } from '../interface/WebProxy';
import { common } from '@kit.AbilityKit';
import { BusinessError, deviceInfo, settings } from '@kit.BasicServicesKit';
import { WebAbilityStage } from '../application/WebAbilityStage';
import { CmdArgsHelper } from '../utils/CmdArgsHelper';
import { CommonDependencyProvider } from '../common/CommonDependencyProvider';
import { GlobalThisHelper } from '../utils/GlobalThisHelper';

const TAG: string = 'WebBaseAbility';

export class WebBaseAbility extends UIAbility implements WebProxy {
  protected xcomponentId: string = '';
  protected startUri: string = '';
  protected windowStage: window.WindowStage | undefined = undefined;
  protected nativeContext: NativeContext =
    JsBindingUtils.getNativeContext(ContextType.kMainProcess);
  protected hideTitleBar: boolean = true;
  protected originWindowId: number = -1;
  protected useDarkMode: boolean = false;
  protected isStateless: boolean = false;
  protected titleButtonVisible: boolean = true;
  protected appId: string = '';
  protected deviceModeChangeEvent: ChangeEventType | undefined = undefined;
  protected initStatus: WindowStatus = WindowStatus.FLOATING;
  protected cmdArgs: Array<string> = [];

  private initParameters(want: Want) {
    if (want && want.parameters) {
      if (want.parameters['xcomponentId'] !== undefined) {
        this.xcomponentId = want.parameters['xcomponentId'] as string;
      }
      if (want.parameters["hideTitleBar"] !== undefined) {
        this.hideTitleBar = want.parameters['hideTitleBar'] as boolean;
      }
      if (want.parameters["useDarkMode"] !== undefined) {
        this.useDarkMode = want.parameters['useDarkMode'] as boolean;
      }
      if (want.parameters["titleButtonVisible"] !== undefined) {
        this.titleButtonVisible = want.parameters['titleButtonVisible'] as boolean;
      }
      if (want.parameters["appId"] !== undefined) {
        this.appId = want.parameters['appId'] as string;
      }
      if (want.parameters["webappWindow"] !== undefined && want.parameters["webappWindow"] !== '') {
        this.appId = "--app-id=" + want.parameters['webappWindow'] as string;
      }
      if (want.parameters["initStatus"] !== undefined) {
        this.initStatus = want.parameters['initStatus'] as WindowStatus;
      }

      let args = want.parameters['cmdArgs'];
      this.cmdArgs = CmdArgsHelper.getCmdArgs(args);
    }

    if (want["uri"]) {
      let storePath = want['uri'] as string;
      // convert storage path to uri
      this.startUri = storePath.replace("file://docs/", "file:///");
    }
  }

  protected getContentPath(): string {
    if (this.nativeContext.IsSupportNodeHandleFeature()) {
      return 'pages/NodeHandleWindow';
    } else {
      return 'pages/Index';
    }
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam) {
    // API 24 can deliver AbilityStage and UIAbility callbacks in either order.
    // Initialize the dependency container before WebAbility requests services.
    if (!GlobalThisHelper.isLaunched()) {
      GlobalThisHelper.appInit(new CommonDependencyProvider(this.context.getApplicationContext()));
    }
    this.initParameters(want);

    if (CheckEmptyUtils.isEmpty(this.xcomponentId)) {
      LogUtil.info(TAG, 'onCreate, Allocate xcomponent id');
      if (want.parameters?.openInNewWindow) {
        this.xcomponentId = WebAbilityStage.X_COMPONENT_ID;
        return;
      }
      let widgetId = this.nativeContext.ExecuteCommand(CommandType.kGetWidget, {}).widget_Id;
      this.xcomponentId = ConfigData.WINDOW_PREFIX + widgetId;
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage) {
    this.windowStage = windowStage;
    this.originWindowId = windowStage?.getMainWindowSync().getWindowProperties().id;
  }

  // implements WebProxy interface
  getWindowStage(): window.WindowStage | undefined {
    return this.windowStage;
  }

  getWindow(): window.Window | undefined {
    return this.windowStage?.getMainWindowSync();
  }

  getWindowContext(): common.Context {
    return this.context;
  }

  getWindowId(): string {
    return this.xcomponentId;
  }

  closeWindow() {
    this.context.terminateSelf()
      .then(() => {
        LogUtil.info(TAG, 'terminate Self id: ' + this.getWindowId());
      })
      .catch((err: BusinessError) => {
        LogUtil.error(TAG, 'Failed to terminate Self: ' + JSON.stringify(err));
      });
  }

  setWindowTitle(title:string) {
    this.context.setMissionLabel(title)
      .catch((err: BusinessError) => {
        LogUtil.error(TAG, 'Failed to set title: ' + JSON.stringify(err));
      });
  }

  createSubWindow(name: string): Promise<window.Window> {
    return new Promise<window.Window>((resolve, reject) => {
      if (!this.windowStage) {
        reject('Failed to get windowStage');
        return;
      }
      this.windowStage.createSubWindow(name)
        .then((data: window.Window) => {
          resolve(data);
        }).catch((error: BusinessError) => {
        reject(error);
      })
    });
  }

  getOriginWindowId(): number {
    return this.originWindowId;
  }

  private systemBarUpdateRunning: boolean = false;
  private pendingSystemBarImmersive: boolean | undefined = undefined;

  // Whether this window form lets the app drive the status bar and the bottom
  // navigation indicator itself. PC desktop has no navigation indicator and the
  // related Window APIs are no-ops on PC/2in1, so it is left to the system.
  public canManageSystemBar(): boolean {
    if (deviceInfo.deviceType !== 'tablet') {
      return false;
    }
    try {
      return settings.getValueSync(this.context, 'isSystemModePc', '',
        settings.domainName.USER_PROPERTY) !== 'true';
    } catch (err) {
      LogUtil.error(TAG, 'Failed to read isSystemModePc: ' + JSON.stringify(err));
      return true;
    }
  }

  // Applies a complete system bar state. When isFullScreen is true the layout
  // extends under the system bars and both the status bar and the bottom
  // navigation indicator are hidden; otherwise every system bar is restored.
  public updateAvoidAreaStatus(isFullScreen: boolean) {
    this.pendingSystemBarImmersive = isFullScreen;
    if (this.systemBarUpdateRunning) {
      return;
    }
    this.systemBarUpdateRunning = true;
    this.runSystemBarUpdates();
  }

  // The Window calls must not run concurrently: hiding wants the layout first,
  // while restoring must enable the bars first and then refresh the layout,
  // otherwise the bars stay hidden after leaving maximize/full-screen.
  private async runSystemBarUpdates() {
    try {
      while (this.pendingSystemBarImmersive !== undefined) {
        const immersive = this.pendingSystemBarImmersive;
        this.pendingSystemBarImmersive = undefined;
        await this.applySystemBarState(immersive);
      }
    } finally {
      this.systemBarUpdateRunning = false;
    }
  }

  private async applySystemBarState(immersive: boolean) {
    let windowClass = this.getWindow();
    if (!windowClass || !this.canManageSystemBar()) {
      return;
    }
    try {
      if (immersive) {
        await windowClass.setWindowLayoutFullScreen(true);
        await windowClass.setSpecificSystemBarEnabled('navigationIndicator', false);
        await windowClass.setSpecificSystemBarEnabled('status', false);
      } else {
        await windowClass.setSpecificSystemBarEnabled('navigationIndicator', true);
        await windowClass.setSpecificSystemBarEnabled('status', true);
        await windowClass.setWindowLayoutFullScreen(false);
      }
      LogUtil.info(TAG, `Applied the system bar state, immersive:${immersive}.`);
    } catch (err) {
      LogUtil.error(TAG, `Failed to apply the system bar state: ${JSON.stringify(err)}`);
    }
  }

  // Keeps the system bars hidden while the window is full-screen or maximized
  // and restores them once the user leaves full-screen/maximize, so exiting a
  // page fullscreen returns to the previous window state.
  public syncSystemBarWithWindowStatus() {
    let windowClass = this.getWindow();
    if (!windowClass || !this.canManageSystemBar()) {
      return;
    }
    try {
      let status = windowClass.getWindowStatus();
      let immersive = status === window.WindowStatusType.FULL_SCREEN ||
        status === window.WindowStatusType.MAXIMIZE;
      this.updateAvoidAreaStatus(immersive);
    } catch (err) {
      LogUtil.error(TAG, 'Failed to sync the system bar: ' + JSON.stringify(err));
    }
  }

  isUIAbility(): boolean {
    return true;
  }

  public setDeviceModeChangeEvent(deviceModeChangeEvent: ChangeEventType | undefined) {
    this.deviceModeChangeEvent = deviceModeChangeEvent;
  }
};
