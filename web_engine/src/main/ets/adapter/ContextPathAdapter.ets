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

import { injectable, inject } from 'inversify';
import environment from '@ohos.file.environment';

import { BaseAdapter } from '../common/BaseAdapter';
import LogUtil from '../utils/LogUtil';
import LogMethod from '../common/LogDecorator';
import { ContextAdapter } from './ContextAdapter';
import { fileUri, picker } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG: string = 'ContextPath';

@injectable()
export class ContextPathAdapter extends BaseAdapter {
  private ctxAdapter: ContextAdapter;

  constructor(@inject(ContextAdapter) ctxAdapter: ContextAdapter) {
    super();
    this.ctxAdapter = ctxAdapter;
  }

  @LogMethod
  getCacheDir(): string {
    return this.ctxAdapter.getContext().getApplicationContext().cacheDir;
  }

  @LogMethod
  getTempDir(): string {
    return this.ctxAdapter.getContext().getApplicationContext().tempDir;
  }

  @LogMethod
  getFilesDir(): string {
    return this.ctxAdapter.getContext().getApplicationContext().filesDir;
  }

  @LogMethod
  getBundleDir(): string {
    return this.ctxAdapter.getContext().bundleCodeDir;
  }

  @LogMethod
  getUserDocumentDir(): string {
    let userDir: string = this.getFilesDir() + '/UserDocument';
    try {
      userDir = environment.getUserDocumentDir();
    } catch (error) {
      LogUtil.error(TAG, `getUserDocumentDir failed: ${JSON.stringify(error)}`);
    }
    return userDir;
  }

  @LogMethod
  getUserDesktopDir(): string {
    let userDir: string = this.getFilesDir() + '/UserDesktop';
    try {
      userDir = environment.getUserDesktopDir();
    } catch (error) {
      LogUtil.error(TAG, `GetUserDesktopDir failed: ${JSON.stringify(error)}`);
    }
    return userDir;
  }

  @LogMethod
  getUserDownloadDir(): string {
    let userDir: string = this.getFilesDir() + '/UserDownload';
    try {
      userDir = environment.getUserDownloadDir();
    } catch (error) {
      LogUtil.error(TAG, `GetUserDownloadDir failed: ${JSON.stringify(error)}`);
    }
    return userDir;
  }

  @LogMethod
  getAppDownloadDir(callback: (downloadDirPath: string) => void) {
    // Adapters are not ArkUI components; use the injected ability/application
    // context, including when Chromium requests its default before UI load.
    const context = this.ctxAdapter.getActiveContext() ?? this.ctxAdapter.getContext();
    try {
      const documentViewPicker = new picker.DocumentViewPicker(context);
      const documentSaveOptions = new picker.DocumentSaveOptions();
      documentSaveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
      documentViewPicker.save(documentSaveOptions).then((result: Array<string>) => {
        callback(result.length > 0 ? new fileUri.FileUri(result[0]).path : '');
      }).catch((err: BusinessError) => {
        LogUtil.error(TAG, `createAppDownloadDir failed: ${JSON.stringify(err)}`);
        callback('');
      });
    } catch (err) {
      LogUtil.error(TAG, `createAppDownloadDir failed: ${JSON.stringify(err)}`);
      callback('');
    }
  }
}
