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

import Base from '@ohos.base';
import CommonEventManager from '@ohos.commonEventManager';
import usb from '@ohos.usbManager';
import { injectable } from 'inversify';
import { BaseAdapter } from '../common/BaseAdapter';
import LogUtil from '../utils/LogUtil';
import LogMethod from '../common/LogDecorator';

interface EventInfo {
  type: number,
  data: Array<usb.USBDevice>
};

const EVENT_DEVICE_ATTATCHED: string = 'usual.event.hardware.usb.action.USB_DEVICE_ATTACHED';
const EVENT_DEVICE_DETATCHED: string = 'usual.event.hardware.usb.action.USB_DEVICE_DETACHED';

@injectable()
export class DeviceAdapter extends BaseAdapter {
  private static TAG: string = 'DeviceAdapter';
  private subscribers: Map<number, CommonEventManager.CommonEventSubscriber> = new Map();
  private pendingSubscribers: Set<number> = new Set();
  private subscribeInfo: CommonEventManager.CommonEventSubscribeInfo = {
    events: [
      CommonEventManager.Support.COMMON_EVENT_USB_DEVICE_ATTACHED,
      CommonEventManager.Support.COMMON_EVENT_USB_DEVICE_DETACHED,
    ]
  };

  @LogMethod
  getDevices(get_devices_cb?: Function) : boolean {
    let devices : Array<usb.USBDevice> = [];
    try {
      devices = usb.getDevices();
      if (get_devices_cb != undefined) {
        get_devices_cb(devices, devices.length);
      }
    } catch (err) {
      LogUtil.error(DeviceAdapter.TAG,
        `Failed to obtain device information, code is ${err.code}, message is ${err.message}`);
      return false;
    }
    return true;
  }

  @LogMethod
  registerHotplugCallback(id: number, hotplug_cb: Function): void {
    this.pendingSubscribers.add(id);
    try {
      CommonEventManager.createSubscriber(this.subscribeInfo, (err, subscriber) => {
        if (err) {
          this.pendingSubscribers.delete(id);
          LogUtil.error(DeviceAdapter.TAG, `CreateSubscriber failed: ${err.code}`);
          return;
        }
        if (!this.pendingSubscribers.delete(id)) {
          return;
        }
        this.subscribers.set(id, subscriber);
        CommonEventManager.subscribe(subscriber, (error, data) => {
          if (this.subscribers.get(id) !== subscriber) {
            return;
          }
          const eventInfo = this.parseEventData(error, data);
          if (eventInfo !== undefined) {
            hotplug_cb(eventInfo.type, eventInfo.data, eventInfo.data.length);
          }
        });
      });
    } catch (err) {
      this.pendingSubscribers.delete(id);
      LogUtil.error(DeviceAdapter.TAG, `CreateSubscriber failed: ${err.code}`);
    }
  }

  private parseEventData(err: Base.BusinessError,
                         data: CommonEventManager.CommonEventData): EventInfo | undefined {
    if (err) {
      LogUtil.error(DeviceAdapter.TAG, `ParseEventData failed, code is ${err.code}, message is ${err.message}`);
      return undefined;
    }

    let eventType: number = 0;
    if (data.event === EVENT_DEVICE_ATTATCHED) {
      eventType = 1;
    } else if (data.event === EVENT_DEVICE_DETATCHED) {
      eventType = 2;
    }
    let devices: Array<usb.USBDevice> = [];
    if (eventType !== 0 && data.data !== undefined) {
      let usbDevice: usb.USBDevice;
      try {
        usbDevice = JSON.parse(data.data) as usb.USBDevice;
        if (eventType === 1) {
          const current = usb.getDevices().find((device: usb.USBDevice) => device.name === usbDevice.name);
          if (current !== undefined) {
            usbDevice = current;
          }
        }
      } catch (error) {
        LogUtil.warn(DeviceAdapter.TAG, 'Invalid USB hotplug event payload');
        return undefined;
      }
      if (usbDevice === undefined) {
        LogUtil.warn(DeviceAdapter.TAG, 'Parse event data error.');
        return undefined;
      }
      devices.push(usbDevice);
      let eventInfo: EventInfo = {
        type: eventType,
        data: devices
      };
      return eventInfo;
    }
    return undefined;
  }

  @LogMethod
  unregisterHotplugCallback(id: number): void {
    this.pendingSubscribers.delete(id);
    const subscriber = this.subscribers.get(id);
    this.subscribers.delete(id);
    if (subscriber === undefined) {
      return;
    }
    try {
      CommonEventManager.unsubscribe(subscriber, (err: Base.BusinessError) => {
        if (err) {
          LogUtil.error(DeviceAdapter.TAG, `Unsubscribe failed: ${err.code}`);
        }
      });
    } catch (err) {
      LogUtil.error(DeviceAdapter.TAG, `Unsubscribe failed: ${err.code}`);
    }
  }

  @LogMethod
  hasRight(deviceName: string): boolean {
    try {
      return usb.hasRight(deviceName);
    } catch (err) {
      LogUtil.error(DeviceAdapter.TAG,
        `hasRight failed, code is ${err.code}, message is ${err.message}`);
      return false;
    }
  }

  @LogMethod
  requestRight(deviceName: string, callback: (isGranted: boolean) => void): void {
    try {
      usb.requestRight(deviceName).then((result: boolean) => callback(result)).catch(() => callback(false));
    } catch(err) {
      LogUtil.error(DeviceAdapter.TAG, `requestRight failed, code is ${err.code}, message is ${err.message}`);
      callback(false);
    }
  }

  @LogMethod
  removeRight(deviceName: string): boolean {
    try {
      return usb.removeRight(deviceName);
    } catch(err) {
      LogUtil.error(DeviceAdapter.TAG, `removeRight failed, code is ${err.code}, message is ${err.message}`);
      return false;
    }
  }

  @LogMethod
  openDevice(device: usb.USBDevice, callback: (pipe: usb.USBDevicePipe) => void): boolean {
    try {
      const devicePipe: usb.USBDevicePipe = usb.connectDevice(device);
      callback(devicePipe);
    } catch(err) {
      LogUtil.error(DeviceAdapter.TAG, `openDevice failed, code is ${err.code}, message is ${err.message}`);
      return false;
    }
    return true;
  }

  @LogMethod
  getRawDescriptor(pipe: usb.USBDevicePipe, callback: (descriptor: Array<number>, length: number) => void): void {
    try {
      const rawDescriptor: Uint8Array = usb.getRawDescriptor(pipe);
      // AKI's std::vector converter uses napi_get_array_length, which accepts
      // JavaScript arrays rather than Uint8Array. Preserve the bytes explicitly.
      const bytes: Array<number> = Array.from(rawDescriptor);
      callback(bytes, bytes.length);
    } catch(err) {
      LogUtil.error(DeviceAdapter.TAG, `getRawDescriptor failed, code is ${err.code}, message is ${err.message}`);
      callback([], 0);
    }
  }

  @LogMethod
  getFileDescriptor(pipe: usb.USBDevicePipe): number {
    try {
      return usb.getFileDescriptor(pipe);
    } catch(err) {
      LogUtil.error(DeviceAdapter.TAG, `getFileDescriptor failed, code is ${err.code}, message is ${err.message}`);
      return -1;
    }
  }

  @LogMethod
  releaseInterface(pipe: usb.USBDevicePipe, iface: usb.USBInterface): number {
    try {
      return usb.releaseInterface(pipe, iface);
    } catch(err) {
      LogUtil.error(DeviceAdapter.TAG, `releaseInterface failed, code is ${err.code}, message is ${err.message}`);
      return -1;
    }
  }

  @LogMethod
  closePipe(pipe: usb.USBDevicePipe): number {
    try {
      return usb.closePipe(pipe);
    } catch(err) {
      LogUtil.error(DeviceAdapter.TAG, `closePipe failed, code is ${err.code}, message is ${err.message}`);
      return -1;
    }
  }
}
