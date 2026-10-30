import Base from '@ohos.base';
import CommonEventManager from '@ohos.commonEventManager';
import usb from '@ohos.usbManager';
import LogUtil from '../utils/LogUtil';

const TAG: string = 'UsbHotplugMonitor';
const EVENT_DEVICE_ATTACHED: string = 'usual.event.hardware.usb.action.USB_DEVICE_ATTACHED';
const EVENT_DEVICE_DETACHED: string = 'usual.event.hardware.usb.action.USB_DEVICE_DETACHED';

/**
 * Keep the platform USB attach listener alive for the application lifetime.
 * OHOS may return an empty usb.getDevices() snapshot to a regular app, so a
 * HID service created after a device was plugged in must be able to replay the
 * attach event that arrived earlier in this app session.
 */
export class UsbHotplugMonitor {
  private static started: boolean = false;
  private static subscriber: CommonEventManager.CommonEventSubscriber | undefined;
  private static devices: Map<string, usb.USBDevice> = new Map();
  private static callbacks: Map<number, Function> = new Map();

  static start(): void {
    if (UsbHotplugMonitor.started) {
      LogUtil.info(TAG, 'USB hotplug monitor start skipped: already started');
      return;
    }
    UsbHotplugMonitor.started = true;
    LogUtil.info(TAG, 'Starting USB hotplug subscriber');
    const subscribeInfo: CommonEventManager.CommonEventSubscribeInfo = {
      events: [
        CommonEventManager.Support.COMMON_EVENT_USB_DEVICE_ATTACHED,
        CommonEventManager.Support.COMMON_EVENT_USB_DEVICE_DETACHED,
      ]
    };
    try {
      CommonEventManager.createSubscriber(subscribeInfo,
        (err: Base.BusinessError, subscriber: CommonEventManager.CommonEventSubscriber) => {
          if (err || subscriber === undefined) {
            UsbHotplugMonitor.started = false;
            LogUtil.error(TAG, `createSubscriber failed: ${err?.code ?? 'unknown'}`);
            return;
          }
          UsbHotplugMonitor.subscriber = subscriber;
          LogUtil.info(TAG, 'USB hotplug subscriber created; subscribing');
          CommonEventManager.subscribe(subscriber,
            (eventError: Base.BusinessError, data: CommonEventManager.CommonEventData) => {
              UsbHotplugMonitor.onEvent(eventError, data);
            });
          LogUtil.info(TAG, 'Application USB hotplug listener subscribed');
        });
    } catch (err) {
      UsbHotplugMonitor.started = false;
      LogUtil.error(TAG, `createSubscriber threw: ${err.code ?? 'unknown'}`);
    }
  }

  static register(id: number, callback: Function): void {
    UsbHotplugMonitor.start();
    UsbHotplugMonitor.callbacks.set(id, callback);
    for (const device of UsbHotplugMonitor.devices.values()) {
      callback(1, [device], 1);
    }
  }

  static unregister(id: number): void {
    UsbHotplugMonitor.callbacks.delete(id);
  }

  static getCachedDevices(): Array<usb.USBDevice> {
    return Array.from(UsbHotplugMonitor.devices.values());
  }

  private static onEvent(err: Base.BusinessError,
                         data: CommonEventManager.CommonEventData): void {
    if (err) {
      LogUtil.error(TAG, `USB event callback failed: ${err.code}, ${err.message}`);
      return;
    }
    const eventName = data.event;
    const eventType = eventName === EVENT_DEVICE_ATTACHED ? 1 :
      eventName === EVENT_DEVICE_DETACHED ? 2 : 0;
    if (eventType === 0) {
      return;
    }
    LogUtil.info(TAG,
      `USB event received: type=${eventType}, payloadLength=${data.data?.length ?? 0}`);
    if (!data.data) {
      LogUtil.error(TAG, `USB event has no device payload: ${eventName}`);
      return;
    }

    let device: usb.USBDevice;
    try {
      device = JSON.parse(data.data) as usb.USBDevice;
    } catch (parseError) {
      LogUtil.error(TAG, `USB event payload is not a device object: ${eventName}`);
      return;
    }
    if (!device?.name) {
      LogUtil.error(TAG, `USB event device has no name: ${eventName}`);
      return;
    }

    if (eventType === 1) {
      // The event payload is authoritative for identity. The current device
      // snapshot is only an optional enrichment because it can be unavailable
      // to non-system applications on some HarmonyOS builds.
      try {
        const current = usb.getDevices().find(
          (item: usb.USBDevice) => item.name === device.name);
        if (current !== undefined) {
          device = current;
        }
      } catch (snapshotError) {
        LogUtil.warn(TAG, 'USB snapshot unavailable; retaining attach payload');
      }
      UsbHotplugMonitor.devices.set(device.name, device);
      LogUtil.info(TAG,
        `USB attach cached: name=${device.name}, vid=${device.vendorId}, pid=${device.productId}, configs=${device.configs?.length ?? 0}`);
    } else {
      UsbHotplugMonitor.devices.delete(device.name);
      LogUtil.info(TAG, `USB detach removed from cache: name=${device.name}`);
    }

    const payload: Array<usb.USBDevice> = [device];
    for (const callback of UsbHotplugMonitor.callbacks.values()) {
      callback(eventType, payload, payload.length);
    }
  }
}
