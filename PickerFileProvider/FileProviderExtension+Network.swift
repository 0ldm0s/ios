//
//  FileProviderExtension+Network.swift
//  PickerFileProvider
//
//  Created by Marino Faggiana on 28/05/18.
//  Copyright © 2018 TWS. All rights reserved.
//
//  Author Marino Faggiana <m.faggiana@twsweb.it>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import FileProvider

extension FileProviderExtension {

    // --------------------------------------------------------------------------------------------
    //  MARK: - Delete
    // --------------------------------------------------------------------------------------------
    
    func deleteFile(withIdentifier itemIdentifier: NSFileProviderItemIdentifier, parentItemIdentifier: NSFileProviderItemIdentifier, metadata: tableMetadata) {
        
        /* ONLY iOS 11*/
        guard #available(iOS 11, *) else { return }
        
        guard let serverUrl = NCManageDatabase.sharedInstance.getServerUrl(metadata.directoryID) else {
            return
        }
        
        let ocNetworking = OCnetworking.init(delegate: nil, metadataNet: nil, withUser: providerData.accountUser, withUserID: providerData.accountUserID, withPassword: providerData.accountPassword, withUrl: providerData.accountUrl)
        ocNetworking?.deleteFileOrFolder(metadata.fileName, serverUrl: serverUrl, success: {
            
            let fileNamePath = self.providerData.directoryUser + "/" + metadata.fileID
            do {
                try self.fileManager.removeItem(atPath: fileNamePath)
            } catch let error {
                print("error: \(error)")
            }
            do {
                try self.fileManager.removeItem(atPath: fileNamePath + ".ico")
            } catch let error {
                print("error: \(error)")
            }
            do {
                try self.fileManager.removeItem(atPath: self.providerData.fileProviderStorageURL!.path + "/" + itemIdentifier.rawValue)
            } catch let error {
                print("error: \(error)")
            }
            
            if metadata.directory {
                let dirForDelete = CCUtility.stringAppendServerUrl(serverUrl, addFileName: metadata.fileName)
                NCManageDatabase.sharedInstance.deleteDirectoryAndSubDirectory(serverUrl: dirForDelete!)
            }
            
            NCManageDatabase.sharedInstance.deleteLocalFile(predicate: NSPredicate(format: "fileID == %@", metadata.fileID))
            NCManageDatabase.sharedInstance.deleteMetadata(predicate: NSPredicate(format: "fileID == %@", metadata.fileID), clearDateReadDirectoryID: nil)
            
        }, failure: { (errorMessage, errorCode) in
            
            // remove itemIdentifier on fileProviderSignalDeleteItemIdentifier
            queueTradeSafe.async(flags: .barrier) {
                fileProviderSignalDeleteContainerItemIdentifier.removeValue(forKey: itemIdentifier)
                fileProviderSignalDeleteWorkingSetItemIdentifier.removeValue(forKey: itemIdentifier)
                self.signalEnumerator(for: [parentItemIdentifier, .workingSet])
            }
        })
    }
    
    // --------------------------------------------------------------------------------------------
    //  MARK: - Favorite
    // --------------------------------------------------------------------------------------------
    
    func settingFavorite(_ favorite: Bool, withIdentifier itemIdentifier: NSFileProviderItemIdentifier, parentItemIdentifier: NSFileProviderItemIdentifier, metadata: tableMetadata) {

        /* ONLY iOS 11*/
        guard #available(iOS 11, *) else { return }
        
        guard let serverUrl = NCManageDatabase.sharedInstance.getServerUrl(metadata.directoryID) else {
            return
        }
        
        let fileNamePath = CCUtility.returnFileNamePath(fromFileName: metadata.fileName, serverUrl: serverUrl, activeUrl: self.providerData.accountUrl)

        let ocNetworking = OCnetworking.init(delegate: nil, metadataNet: nil, withUser: providerData.accountUser, withUserID: providerData.accountUserID, withPassword: providerData.accountPassword, withUrl: providerData.accountUrl)
        ocNetworking?.settingFavorite(fileNamePath, favorite: favorite, success: {
                    
            // Change DB
            metadata.favorite = favorite
            _ = NCManageDatabase.sharedInstance.addMetadata(metadata)                    
            
        }, failure: { (errorMessage, errorCode) in
            
            // Errore, remove from listFavoriteIdentifierRank
            listFavoriteIdentifierRank.removeValue(forKey: itemIdentifier.rawValue)

            let item = FileProviderItem(metadata: metadata, parentItemIdentifier: parentItemIdentifier, providerData: self.providerData)
            
            queueTradeSafe.async(flags: .barrier) {
                fileProviderSignalUpdateContainerItem[item.itemIdentifier] = item
                fileProviderSignalUpdateWorkingSetItem[item.itemIdentifier] = item
                self.signalEnumerator(for: [item.parentItemIdentifier, .workingSet])
            }
            
        })
    }
    
    // --------------------------------------------------------------------------------------------
    //  MARK: - Upload
    // --------------------------------------------------------------------------------------------
    
    func uploadStart(_ fileID: String!, task: URLSessionUploadTask!, serverUrl: String!) {
     
        /* ONLY iOS 11*/
        guard #available(iOS 11, *) else { return }

        guard let metadata = NCManageDatabase.sharedInstance.getMetadata(predicate: NSPredicate(format: "fileID = %@", fileID)) else {
            return
        }
        
        guard let parentItemIdentifier = providerData.getParentItemIdentifier(metadata: metadata) else {
            return
        }
        
        let item = FileProviderItem(metadata: metadata, parentItemIdentifier: parentItemIdentifier, providerData: providerData)

        NSFileProviderManager.default.register(task, forItemWithIdentifier: NSFileProviderItemIdentifier(item.itemIdentifier.rawValue)) { (error) in }
        
        let url = URL(string: providerData.fileProviderStorageURL!.path + "/"  + item.itemIdentifier.rawValue + "/" + item.filename)
        self.outstandingUploadTasks[url!] = task
        
        queueTradeSafe.async(flags: .barrier) {
            fileProviderSignalUpdateContainerItem[item.itemIdentifier] = item
            fileProviderSignalUpdateWorkingSetItem[item.itemIdentifier] = item
            self.signalEnumerator(for: [item.parentItemIdentifier, .workingSet])
        }
    }
    
    func uploadFileSuccessFailure(_ fileName: String!, fileID: String!, assetLocalIdentifier: String!, serverUrl: String!, selector: String!, selectorPost: String!, errorMessage: String!, errorCode: Int) {
        
        /* ONLY iOS 11*/
        guard #available(iOS 11, *) else { return }
        
        guard let metadata = NCManageDatabase.sharedInstance.getMetadata(predicate: NSPredicate(format: "account = %@ AND fileID = %@", providerData.account, fileID)) else {
            return
        }
        
        guard let parentItemIdentifier = providerData.getParentItemIdentifier(metadata: metadata) else {
            return
        }
        
        // remove task on outstandingUploadTasks
        let itemIdentifier = providerData.getItemIdentifier(metadata: metadata)
        let url = URL(string: providerData.fileProviderStorageURL!.path + "/"  + itemIdentifier.rawValue + "/" + fileName)
        outstandingUploadTasks.removeValue(forKey: url!)
        
        if errorCode == 0 {
            
            // importDocument
            if (selectorPost == selectorPostImportDocument) {
                
                NCManageDatabase.sharedInstance.deleteQueueUpload(assetLocalIdentifier: assetLocalIdentifier, selector: selector)
                
                // Rename directory file
                if fileManager.fileExists(atPath: providerData.fileProviderStorageURL!.path + "/" + assetLocalIdentifier) {
                    let itemIdentifier = providerData.getItemIdentifier(metadata: metadata)
                    _ = moveFile(providerData.fileProviderStorageURL!.path + "/" + assetLocalIdentifier, toPath: providerData.fileProviderStorageURL!.path + "/" + itemIdentifier.rawValue)
                }
                
                queueTradeSafe.sync(flags: .barrier) {
                    let itemIdentifier = NSFileProviderItemIdentifier(assetLocalIdentifier)
                    fileProviderSignalDeleteContainerItemIdentifier[itemIdentifier] = itemIdentifier
                    fileProviderSignalDeleteWorkingSetItemIdentifier[itemIdentifier] = itemIdentifier
                }
                
            }
            
            // itemChanged
            if (selectorPost == selectorPostItemChanged) {
                
                let filePathItemIdentifier = providerData.fileProviderStorageURL!.path + "/" + providerData.getItemIdentifier(metadata: metadata).rawValue + "/" + metadata.fileName
                _ = self.copyFile(filePathItemIdentifier, toPath: providerData.directoryUser + "/" + metadata.fileID)
            }
            
            NCManageDatabase.sharedInstance.setLocalFile(fileID: fileID, date: nil, exifDate: nil, exifLatitude: nil, exifLongitude: nil, fileName: nil, etag: metadata.etag, etagFPE: metadata.etag)
            
            let item = FileProviderItem(metadata: metadata, parentItemIdentifier: parentItemIdentifier, providerData: providerData)

            queueTradeSafe.sync(flags: .barrier) {
                fileProviderSignalUpdateContainerItem[item.itemIdentifier] = item
                fileProviderSignalUpdateWorkingSetItem[item.itemIdentifier] = item
            }
            
            uploadFile()
            
        } else {
            
            // importDocument
            if (selectorPost == selectorPostImportDocument) {
                
                NCManageDatabase.sharedInstance.unlockQueueUpload(assetLocalIdentifier: assetLocalIdentifier)
            }
            
            let item = FileProviderItem(metadata: metadata, parentItemIdentifier: parentItemIdentifier, providerData: providerData)
            
            queueTradeSafe.sync(flags: .barrier) {
                fileProviderSignalUpdateContainerItem[item.itemIdentifier] = item
                fileProviderSignalUpdateWorkingSetItem[item.itemIdentifier] = item
            }
        }
        
        self.signalEnumerator(for: [parentItemIdentifier, .workingSet])
    }
    
    func uploadFile() {
        
        let queueInLock = NCManageDatabase.sharedInstance.getQueueUploadInLock()
        if queueInLock != nil && queueInLock!.count == 0 {
            
            let metadataNetQueue = NCManageDatabase.sharedInstance.lockQueueUpload(selector: selectorUploadFile, withPath: true)
            if  metadataNetQueue != nil {
                
                if self.copyFile(metadataNetQueue!.path, toPath: providerData.directoryUser + "/" + metadataNetQueue!.fileName) == nil {
                    
                    CCNetworking.shared().uploadFile(metadataNetQueue!.fileName, serverUrl: metadataNetQueue!.serverUrl, fileID: metadataNetQueue!.assetLocalIdentifier, assetLocalIdentifier: metadataNetQueue!.assetLocalIdentifier, session: metadataNetQueue!.session, taskStatus: metadataNetQueue!.taskStatus, selector: metadataNetQueue!.selector, selectorPost: metadataNetQueue!.selectorPost, errorCode: 0, delegate: self)
                    
                } else {
                    // file not present, delete record Upload Queue
                    NCManageDatabase.sharedInstance.deleteQueueUpload(path: metadataNetQueue!.path)
                }
            }
        }
    }
    
    func verifyUploadQueueInLock() {
        
        let tasks = CCNetworking.shared().getUploadTasksExtensionSession()
        if tasks!.count == 0 {
            let records = NCManageDatabase.sharedInstance.getQueueUpload(predicate: NSPredicate(format: "account = %@ AND selector = %@ AND lock == true AND path != nil", providerData.account, selectorUploadFile))
            if records != nil && records!.count > 0 {
                NCManageDatabase.sharedInstance.unlockAllQueueUploadWithPath()
            }
        }
    }

}
