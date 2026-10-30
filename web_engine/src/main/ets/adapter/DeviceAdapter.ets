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

import usb from '@ohos.usbManager';
import { injectable } from 'inversify';
import { BaseAdapter } from '../common/BaseAdapter';
import LogUtil from '../utils/LogUtil';
import LogMethod from '../common/LogDecorator';
import { UsbHotplugMonitor } from './UsbHotplugMonitor';

@injectable()
export class DeviceAdapter extends BaseAdapter {
  private static TAG: string = 'DeviceAdapter';

  @LogMethod
  getDevices(get_devices_cb?: Function) : boolean {
    let devices : Array<usb.USBDevice> = [];
    let snapshotSucceeded: boolean = true;
    try {
      devices = usb.getDevices();
    } catch (err) {
      LogUtil.error(DeviceAdapter.TAG,
        `Failed to obtain device information, code is ${err.code}, message is ${err.message}`);
      snapshotSucceeded = false;
    }
    const knownNames = new Set<string>(devices.map((device: usb.USBDevice) => device.name));
    for (const device of UsbHotplugMonitor.getCachedDevices()) {
      if (!knownNames.has(device.name)) {
        devices.push(device);
        knownNames.add(device.name);
      }
    }
    LogUtil.info(DeviceAdapter.TAG,
      `USB enumeration snapshot=${snapshotSucceeded}, listed=${devices.length}, cached=${UsbHotplugMonitor.getCachedDevices().length}`);
    if (get_devices_cb != undefined) {
      get_devices_cb(devices, devices.length);
    }
    return snapshotSucceeded || devices.length > 0;
  }

  @LogMethod
  registerHotplugCallback(id: number, hotplug_cb: Function): void {
    UsbHotplugMonitor.register(id, hotplug_cb);
    LogUtil.info(DeviceAdapter.TAG,
      `USB hotplug callback registered: id=${id}, cached=${UsbHotplugMonitor.getCachedDevices().length}`);
  }

  @LogMethod
  unregisterHotplugCallback(id: number): void {
    UsbHotplugMonitor.unregister(id);
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
