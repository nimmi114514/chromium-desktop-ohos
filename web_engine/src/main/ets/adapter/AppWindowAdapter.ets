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

import bundleManager from '@ohos.bundle.bundleManager';
import { inject, injectable } from 'inversify';
import { BusinessError } from '@ohos.base';
import { display, NodeContent, window } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import Want from '@ohos.app.ability.Want';
import { BaseAdapter } from '../common/BaseAdapter';
import LogUtil from '../utils/LogUtil';
import { AbilityManager } from '../common/AbilityManager';
import LogMethod from '../common/LogDecorator';
import { StartOptions } from '@kit.AbilityKit';
import { NewWindowParam, PointCoordinate, WindowBound, kAbilityMap,
  AbilityType } from '../interface/CommonInterface';
import LaunchHelper from '../utils/LaunchHelper';
import { ContextAdapter } from './ContextAdapter';
import { DeviceInfoAdapter } from "../adapter/DeviceInfoAdapter";
import { NativeThemeAdapter } from './NativeThemeAdapter';
import { NodeHandleManager } from '../common/NodeHandleManager';
import { kTitleBarHeightVP } from '../common/Constants';
import CheckEmptyUtils from '../utils/CheckEmptyUtils';

const TAG: string = 'AppWindow';

@injectable()
export class AppWindowAdapter extends BaseAdapter {
  private abilityManager: AbilityManager;
  private bundleName: string = 'com.example.ohos.chromium';
  private bundleFlags = bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION |
                        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_METADATA;
  private queryWindowNum: number = 10;                      
  private ctxAdapter: ContextAdapter;
  private deviceInfoAdapter: DeviceInfoAdapter;
  private themeAdapter: NativeThemeAdapter;
  private nodeHandleManager: NodeHandleManager;

  constructor(
    @inject(AbilityManager) abilityManager: AbilityManager,
    @inject(ContextAdapter) ctxAdapter: ContextAdapter,
    @inject(DeviceInfoAdapter) deviceInfoAdapter: DeviceInfoAdapter,
    @inject(NativeThemeAdapter) themeAdapter: NativeThemeAdapter,
    @inject(NodeHandleManager) nodeHandleManager: NodeHandleManager
  ) {
    super();
    this.abilityManager = abilityManager;
    this.ctxAdapter = ctxAdapter;
    this.deviceInfoAdapter = deviceInfoAdapter;
    this.themeAdapter = themeAdapter;
    this.nodeHandleManager = nodeHandleManager;

    try {
      bundleManager.getBundleInfoForSelf(this.bundleFlags).then((data) => {
        this.bundleName = data?.name;
      }).catch((err: BusinessError) => {
        LogUtil.error(TAG, `getBundleInfoForSelf failed. Cause: ${err.message}`);
      });
    } catch (err) {
      let message = (err as BusinessError).message;
      LogUtil.error(TAG, `getBundleInfoForSelf failed.: ${message}`);
    }
  }

  private getWindow(id: number): window.Window | undefined {
    return this.abilityManager.getProxy(id)?.getWindow();
  }

  private backgroundColor(useDarkMode: boolean): string {
    if (useDarkMode || this.themeAdapter.isDarkMode()) {
      return NativeThemeAdapter.DARK_BACKGROUND_COLOR;
    }
    return NativeThemeAdapter.LIGHT_BACKGROUND_COLOR;
  }

  @LogMethod
  createWindow(param: NewWindowParam) {
    LogUtil.info(TAG, `[ohoswindow] in AppWindowAdapter createWindow, param is ${JSON.stringify(param)}`);
    let abilityName: string = kAbilityMap.get(param.ability_type) ?? 'EntryAbility';
    const want: Want = {
      bundleName: this.bundleName,
      abilityName: abilityName,
      parameters: {
        'xcomponentId': param.window_id,
        'hideTitleBar': param.hide_title_bar,
        'useDarkMode': param.use_dark_mode,
        'titleButtonVisible': param.caption_button_visible,
        instanceKey: param.window_id,
        'webappWindow': param.app_id,
        'initStatus': param.status
      }
    };

    let windowClass = this.ctxAdapter.getActiveProxy().getWindow();
    const windowProp = windowClass?.getWindowProperties();
    let xComTop: number = 0;
    let uiContext = windowClass?.getUIContext();

    if (this.nativeContext.IsSupportNodeHandleFeature() &&
      !CheckEmptyUtils.isWindowBoundsEmpty(param.bounds) &&
      !param.hide_title_bar) {
      // Keep the bounds saved in Chromium consistent with the bounds in windowRectChange,
      // otherwise the window will shift downwards the next time it is created.
      xComTop = uiContext ? uiContext.vp2px(kTitleBarHeightVP.kDefault) : xComTop;
    }

    let options: StartOptions = {
      windowLeft: param.bounds.left,
      windowTop: param.bounds.top - xComTop,
      windowWidth: param.bounds.width,
      windowHeight: param.bounds.height + xComTop,
      minWindowWidth: uiContext ?
        uiContext.px2vp(param.window_limit.min_width === 0 ? 0 :
          param.window_limit.min_width) : 0,
      minWindowHeight: uiContext ?
        uiContext.px2vp(param.window_limit.min_height === 0 ? 0 :
          param.window_limit.min_height + xComTop) : 0,
      maxWindowWidth: uiContext ?
        uiContext.px2vp(param.window_limit.max_width === 0 ? 0 :
          param.window_limit.max_width) : 0,
      maxWindowHeight: uiContext ?
        uiContext.px2vp(param.window_limit.max_height === 0 ? 0 :
          param.window_limit.max_height + xComTop) : 0,
      startWindowBackgroundColor: this.backgroundColor(param.use_dark_mode),
    }
    LaunchHelper.LaunchWithOptions(this.ctxAdapter.getActiveContext(), want, options);
  }

  @LogMethod
  closeWindow(id: number) {
    let proxy = this.abilityManager.getProxy(id);
    proxy?.closeWindow();
  }

  @LogMethod
  showWindow(id: number) {
    LogUtil.info(TAG, `[ohoswindow] in AppWindowAdapter showWindow, id is ${id}`);
    let windowClass = this.getWindow(id);
    if (!windowClass) {
      LogUtil.error(TAG, `[ohoswindow] Failed to obtain the main window ${id}`);
      return;
    }

    windowClass.showWindow()
      .catch((err: BusinessError) => {
        LogUtil.error(TAG, '[ohoswindow] Failed to show the window. Cause:' + JSON.stringify(err));
      });
  }

  @LogMethod
  activateWindow(id: number) {
    LogUtil.info(TAG, `[ohoswindow] in AppWindowAdapter activateWindow, id is ${id}`);
    this.showWindow(id);
  }

  @LogMethod
  setFullscreen(id: number) {
    let windowClass = this.getWindow(id);
    if (!windowClass) {
      LogUtil.error(TAG, 'Failed to obtain the main window.');
      return;
    }

    if (this.deviceInfoAdapter.isNormalWindowMode()) {
      this.abilityManager.getProxy(id)?.updateAvoidAreaStatus(true);
    }

    if (deviceInfo.sdkApiVersion >= 14) {
      windowClass.maximize(window.MaximizePresentation.ENTER_IMMERSIVE_DISABLE_TITLE_AND_DOCK_HOVER)
        .catch((err: BusinessError) => {
          LogUtil.error(TAG, 'Failed to maximize the window. Cause:' + JSON.stringify(err));
        });
    } else {
      windowClass.maximize(window.MaximizePresentation.ENTER_IMMERSIVE)
        .catch((err: BusinessError) => {
          LogUtil.error(TAG, 'Failed to maximize the window. Cause:' + JSON.stringify(err));
        });
    }
  }

  @LogMethod
  setBounds(id: number, bounds: WindowBound) {
    let windowClass = this.getWindow(id);
    if (!windowClass) {
      LogUtil.error(TAG, 'Failed to obtain the main window.');
      return;
    }

    const windowProp = windowClass.getWindowProperties();
    let xComBorder: number = windowProp?.drawableRect.left || 0;
    let xComTop: number = windowProp?.drawableRect.top || 0;
    bounds.left -= xComBorder;
    bounds.top -= xComTop;
    bounds.width = bounds.width + xComBorder + xComBorder;
    bounds.height = bounds.height + xComBorder + xComTop;

    try {
      if (windowClass.getWindowStatus() !== window.WindowStatusType.MAXIMIZE &&
        windowClass.getWindowStatus() !== window.WindowStatusType.FULL_SCREEN) {
        windowClass.moveWindowToAsync(bounds.left, bounds.top)
          .then(() => {
            if (windowClass?.getWindowStatus() !== window.WindowStatusType.MAXIMIZE &&
              windowClass?.getWindowStatus() !== window.WindowStatusType.FULL_SCREEN) {
              windowClass?.resizeAsync(bounds.width, bounds.height)
                .catch((err: BusinessError) => {
                  LogUtil.error(TAG,
                    'Failed to change the window size. Cause:' + JSON.stringify(err) + ' window status:' +
                    windowClass?.getWindowStatus());
                });
            }
          }).catch((err: BusinessError) => {
          LogUtil.error(TAG, 'Failed to move the window. Cause:' + JSON.stringify(err) + ' window status:' +
          windowClass?.getWindowStatus());
        });
      }
    } catch (exception) {
      LogUtil.error(TAG, 'move the window exception. Cause:' + JSON.stringify(exception));
    }
  }

  @LogMethod
  setEnabled(enable: boolean, id: number) {
    let windowClass = this.getWindow(id);
    if (!windowClass) {
      LogUtil.error(TAG, 'Failed to obtain the main window.');
      return;
    }
    windowClass.setWindowTouchable(enable)
      .catch((err: BusinessError) => {
        LogUtil.error(TAG, 'Failed to set the window to be touchable. Cause:' + JSON.stringify(err));
      });
  }

  @LogMethod
  setWindowLimits(minWidth: number,
                  minHeight: number,
                  maxWidth: number,
                  maxHeight: number,
                  id: number) {
    let windowClass = this.getWindow(id);
    if (!windowClass) {
      LogUtil.error(TAG, 'Failed to obtain the main window.');
      return;
    }

    const windowProp = windowClass.getWindowProperties();
    let xComBorder: number = windowProp?.drawableRect.left || 0;
    let xComTop: number = windowProp?.drawableRect.top || 0;

    try {
      let windowLimits: window.WindowLimits = {
        minWidth: minWidth === 0 ? minWidth : minWidth + xComBorder + xComBorder,
        minHeight: minHeight === 0 ? minHeight : minHeight + xComTop + xComBorder,
        maxWidth: maxWidth === 0 ? maxWidth : maxWidth + xComBorder + xComBorder,
        maxHeight: maxHeight === 0 ? maxHeight : maxHeight + xComTop + xComBorder,
      };
      windowClass.setWindowLimits(windowLimits)
        .catch((err: BusinessError) => {
          LogUtil.error(TAG, 'Failed to change the window limits. Cause: ' + JSON.stringify(err));
        });
    } catch (exception) {
      LogUtil.error(TAG, 'change the window limits exception. Cause:' + JSON.stringify(exception));
    }
  }

  @LogMethod
  maximize(id: number) {
    let windowClass = this.getWindow(id);
    if (!windowClass) {
      LogUtil.error(TAG, 'Failed to obtain the main window.');
      return;
    }

    if (windowClass.getWindowStatus() === window.WindowStatusType.MAXIMIZE) {
      return;
    }

    try {
      windowClass.maximize(window.MaximizePresentation.EXIT_IMMERSIVE).then(() => {
        LogUtil.info(TAG, 'Succeeded in maximizing the window.');
      }).catch((err: BusinessError) => {
        LogUtil.error(TAG, 'Failed to maximize the window. Cause:' + JSON.stringify(err));
      });

      if (!this.deviceInfoAdapter.isPcMode()) {
        this.abilityManager.getProxy(id)?.updateAvoidAreaStatus(false);
      }
    } catch (exception) {
      LogUtil.error(TAG, 'maximize the window exception. Cause:' + JSON.stringify(exception));
    }
  }

  @LogMethod
  unMaximize(id: number) {
    let windowClass = this.getWindow(id);
    if (!windowClass) {
      LogUtil.error(TAG, 'Failed to obtain the main window.');
      return;
    }

    try {
      windowClass.recover().then(() => {
        LogUtil.info(TAG, 'Succeeded in setting the system bar to be invisible.');
      }).catch((err: BusinessError) => {
        LogUtil.error(TAG, 'Failed to recover the window. Cause: ' + JSON.stringify(err));
      });
    } catch (exception) {
      LogUtil.error(TAG, 'recover the window exception. Cause:' + JSON.stringify(exception));
    }
  }

  @LogMethod
  minimize(id: number) {
    let windowClass = this.getWindow(id);
    if (!windowClass) {
      LogUtil.error(TAG, 'Failed to obtain the main window.');
      return;
    }
    windowClass.minimize()
      .catch((err: BusinessError) => {
        LogUtil.error(TAG, 'Failed to minimize the window. Cause: ' + JSON.stringify(err));
      });
  }

  @LogMethod
  setTitle(title:string, id: number) {
    let proxy = this.abilityManager.getProxy(id);
    proxy?.setWindowTitle(title);
  }

  @LogMethod
  relaunch(): boolean {
    let applicationContext = this.ctxAdapter.getContext().getApplicationContext();
    let want: Want = {
      bundleName: this.bundleName,
      abilityName: 'EntryAbility'
    };
    try {
      applicationContext.restartApp(want);
      return true;
    } catch (err) {
      LogUtil.error(TAG, 'restartApp fail, error:' + JSON.stringify(err))
      return false;
    }
  }

  @LogMethod
  startWindowMoving(id: number) {
    let window = this.getWindow(id);
    if (deviceInfo.sdkApiVersion >= 14) {
      window?.startMoving().then(() => {
      }).catch((err: BusinessError) => {
        LogUtil.error(TAG, `startWindowMoving fail, error info: ${JSON.stringify(err)}`);
      });
    } else {
      LogUtil.error(TAG, 'startWindowMoving fail, sdkApiVersion is less than 14');
    }
  }

  @LogMethod
  startWindowMovingWithOffset(id: number, offsetX: number, offsetY: number) {
    let window = this.getWindow(id);
    if (deviceInfo.sdkApiVersion >= 15) {
      window?.startMoving(offsetX, offsetY).then(() => {
      }).catch((err: BusinessError) => {
        LogUtil.error(TAG, `startWindowMovingWithOffset fail, error info: ${JSON.stringify(err)}`);
      });
    } else {
      LogUtil.error(TAG, 'startWindowMovingWithOffset fail, sdkApiVersion is less than 15');
    }
  }

  @LogMethod
  getWindowsByCoordinate(coordinate: PointCoordinate,
                         callback: (windowIds: Array<string>) => void) {
    let windowIds = new Array<string>();
    if (deviceInfo.sdkApiVersion >= 14) {
      try {
        window.getWindowsByCoordinate(coordinate.displayId, this.queryWindowNum,
          coordinate.x, coordinate.y).then((windows) => {
          for (let win of windows) {
            let originWindowId: number = win.getWindowProperties().id
            let windowId = this.abilityManager.getWindowIdByOriginWindow(originWindowId);
            if (windowId) {
              windowIds.push(windowId);
            }
          }
          callback(windowIds);
        }).catch((err: BusinessError) => {
          LogUtil.error(TAG, 'window.getWindowsByCoordinate fail, code:' + JSON.stringify(err.code) +
            ',message:' + JSON.stringify(err.message));
          callback(windowIds);
        });
      } catch (err) {
        LogUtil.error(TAG, 'getWindowsByCoordinate fail, error:' + JSON.stringify(err));
        callback(windowIds);
      }
    } else {
      LogUtil.error(TAG, 'getWindowsByCoordinate fail, sdkApiVersion is less than 14');
      callback(windowIds);
    }
	}

  @LogMethod
  restore(id: number) {
    let windowClass = this.getWindow(id);
    if (!windowClass) {
      LogUtil.error(TAG, 'Failed to obtain the main window.');
      return;
    }
    windowClass.restore().then(() => {
      LogUtil.info(TAG, 'Succeeded in restoring the window.');
    }).catch((err: BusinessError) => {
      LogUtil.error(TAG, 'Failed to restore the window. Cause: ' + JSON.stringify(err));
    });
  }

  @LogMethod
  getOriginWindowIds(windowIds: Array<number>): Array<number> {
    let originWindowIds = new Array<number>();
    try {
      for (let i = 0; i < windowIds.length; i++) {
        let originWindowId = this.abilityManager.getProxy(windowIds[i])?.getOriginWindowId();
        originWindowIds.push(originWindowId ? originWindowId : -1);
      }
    } catch (err) {
      let message = (err as BusinessError).message;
      LogUtil.error(TAG, `getOriginWindowIds failed.: ${message}`);
    }
    return originWindowIds;
  }

  @LogMethod
  shiftWindowMouseEvent(sourceId: number, targetId: number,
    callback: (result: boolean) => void): void {
    if (deviceInfo.sdkApiVersion >= 15) {
      try {
        let sourceOriginWindowId = this.abilityManager.getProxy(sourceId)?.getOriginWindowId();
        let targetOriginWindowId = this.abilityManager.getProxy(targetId)?.getOriginWindowId();
        window.shiftAppWindowPointerEvent(sourceOriginWindowId, targetOriginWindowId).then(() => {
          LogUtil.info(TAG, 'shiftWindowEvent success.');
          callback(true);
        }).catch((err: BusinessError) => {
          LogUtil.error(TAG, 'Failed to shiftWindowEvent. Cause: ' + JSON.stringify(err));
          callback(false);
        })
      } catch (err) {
        let message = (err as BusinessError).message;
        LogUtil.error(TAG, `shiftWindowEvent failed.: ${message}`);
        callback(false);
      }
    } else {
      LogUtil.error(TAG, 'shiftWindowEvent fail, sdkApiVersion is less than 15');
      callback(false);
    }
  }

  @LogMethod
  shiftWindowTouchEvent(sourceId: number, targetId: number,
    fingerId: number, callback: (result: boolean) => void): void {
    if (deviceInfo.sdkApiVersion >= 20) {
      try {
        let sourceOriginWindowId = this.abilityManager.getProxy(sourceId)?.getOriginWindowId();
        let targetOriginWindowId = this.abilityManager.getProxy(targetId)?.getOriginWindowId();
        window.shiftAppWindowTouchEvent(sourceOriginWindowId, targetOriginWindowId, fingerId).then(() => {
          LogUtil.info(TAG, 'shiftWindowTouchEvent success.');
          callback(true);
        }).catch((err: BusinessError) => {
          LogUtil.error(TAG, 'Failed to shiftWindowTouchEvent. Cause: ' + JSON.stringify(err));
          callback(false);
        })
      } catch (err) {
        let message = (err as BusinessError).message;
        LogUtil.error(TAG, `shiftWindowTouchEvent failed.: ${message}`);
        callback(false);
      }
    } else {
      LogUtil.error(TAG, 'shiftWindowTouchEvent fail, sdkApiVersion is less than 20');
      callback(false);
    }
  }

  bind(id: string, callback: (nodeContent: NodeContent | undefined) => void) {
    let nodeContent = this.nodeHandleManager.getNodeContent(id);
    if (!nodeContent) {
      LogUtil.warn(TAG, 'bind node handle with node content failed, not find node content for id' + id);
      callback(undefined);
      return;
    }
    callback(nodeContent);
  }

  @LogMethod
  unbind(id: string, callback: (nodeContent: NodeContent | undefined) => void) {
    let nodeContent = this.nodeHandleManager.getNodeContent(id);
    if (!nodeContent) {
      LogUtil.warn(TAG, 'unbind node handle with node content failed, not find node content for id' + id);
      callback(undefined);
      return;
    }
    callback(nodeContent);
  }
};
