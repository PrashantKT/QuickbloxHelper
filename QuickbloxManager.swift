//
//  QuicjbloxManager.swift
//

//-----------------------------------------------------------------------

// MARK: - Frameworks: QuickbloxManager

//-----------------------------------------------------------------------

import UIKit
import Quickblox
import QuickbloxWebRTC

//-----------------------------------------------------------------------

// MARK: - Protocol: QuickbloxManagerDelegate

//-----------------------------------------------------------------------

@objc protocol QuickbloxManagerDelegate: NSObjectProtocol {
    @objc optional func chatReceive(_ message: QBChatMessage)
    @objc optional func reloadData()
}

//-----------------------------------------------------------------------

// MARK: - Class: QuickbloxManager

//-----------------------------------------------------------------------

@objc class QuickbloxManager: NSObject {
    
    //-----------------------------------------------------------------------
    
    // MARK: - Structures
    
    //-----------------------------------------------------------------------
    
    struct UserWithChatMessages {
        var user: QBUUser? = nil
        var arrChatMessages = [QBChatMessage]()
        var chatDialog: QBChatDialog? = nil
        var profileImage: UIImage? = nil
    }
    
    // Group Chat Structures
    struct UserWithGroupChatMessages {
        var arrGroupChatMessages = [QBChatMessage]()
        var groupChatDialog: QBChatDialog? = nil
        var profileImage: UIImage? = nil
        var groupName: String? = nil
        var arrGroupMembers = [NSNumber]()
        var imageDownloadBlobID:String?
        var users: [QBUUser] = []
    }

    //-----------------------------------------------------------------------
    
    // MARK: - Properties
    
    //-----------------------------------------------------------------------
    
    static let sharedManager = QuickbloxManager()
    var delegate: QuickbloxManagerDelegate?
    fileprivate let quickBloxUser = "QuickBloxUser"
    var currentUser: QBUUser? {
        
        get {
            if let data = AppUserDefaults.getObjectAtRoot(forKey: quickBloxUser) as? Data,
                let user = NSKeyedUnarchiver.unarchiveObject(with: data) as? QBUUser {
                return user
            }
            return nil
        }
        
        set {
            if newValue != nil {
                let data = NSKeyedArchiver.archivedData(withRootObject: newValue!)
                AppUserDefaults.saveObject(atRoot: data, forKey: quickBloxUser)
            }
        }
    }
    
    var currentChatDialog: QBChatDialog? = nil
    var arrUsersWithChatMessages = [UserWithChatMessages]()
    var arrSearchContacts = [QBUUser]()
    var arrAllContacts = [QBUUser]()

    var selectedUserWithChatMessages = UserWithChatMessages(user: nil, arrChatMessages: [], chatDialog: nil, profileImage: nil)

    var sessionForAudioVideoCall: QBRTCSession? = nil
    var timer: Timer? = nil
    var strCallTime = ""
    var callTimeInterval: TimeInterval = 0
    var isFromCall = false
    
    //-----------------------------------------------------------------------
    
    // MARK: - Group Chat Properties
    
    //-----------------------------------------------------------------------
    
    var currentGroupChatDialog: QBChatDialog? = nil
    var arrGroupUsersWithChatMessages = [UserWithGroupChatMessages]()
    var selectedGroupChat = UserWithGroupChatMessages(arrGroupChatMessages: [], groupChatDialog: nil, profileImage: nil, groupName: nil, arrGroupMembers: [], imageDownloadBlobID: nil,users:[])


    
    
    
    var removeAllData: Bool = false {
        didSet{
            if removeAllData {
                currentUser = nil
                currentChatDialog = nil
                arrUsersWithChatMessages = []
                AppUserDefaults.removeObjectAtRoot(forKey: quickBloxUser)
            }
        }
    }
    
}

//-----------------------------------------------------------------------

// MARK: - Extension: Public Methods

//-----------------------------------------------------------------------

extension QuickbloxManager {
    
    //-----------------------------------------------------------------------
    
    func signUP(dictUserDetails: [String: Any], success: ((QBUUser) -> Void)?, failure: ((Error) -> Void)?) {
        
        let user = QBUUser()
        
        // First Name
        if let firstName = dictUserDetails[kUserFirstName] {
            var strFullName = "\(firstName)"
            
            // Last Name
            if let lastName = dictUserDetails[kUserLastName] {
                strFullName += " \(lastName)"
            }
            user.fullName = strFullName
        }
        
        // Email, Password
        if let email = dictUserDetails[kUserEmail] {
            user.email = "\(email)"
            user.login = "\(email)"
        }
        
        if let password = dictUserDetails[kUserPassword] {
            user.password = "\(password)"
        }
        
        QBRequest.signUp(user, successBlock: { (response, user) in
            if success != nil {
                success!(user)
            }
        }) { (response) in
            if failure != nil, response.error?.error != nil {
                failure!((response.error?.error)!)
            }
        }
        
    }
    
    //-----------------------------------------------------------------------
    
    func logIn(dictUserDetails: [String: Any], success: ((QBUUser) -> Void)?, failure: ((Error) -> Void)?) {
        
        if let email = dictUserDetails[kUserEmail], let password = dictUserDetails[kUserPassword] {
            QBRequest.logIn(withUserEmail: email as! String, password: password as! String, successBlock: { (response, user) in
                self.currentUser = user
                self.currentUser?.password = kQuickBloxPassword.base64Decoded()
                if success != nil {
                    success!(user)
                }
//                if let strURL = dictUserDetails[loginKeys.kProfileImage] as? String {
//                    self.uploadUserProfileImage(strURL: strURL)
//                }
                self.logInWithChat()
            }) { (response) in
                if failure != nil, response.error?.error != nil {
                    failure!((response.error?.error)!)
                }
            }
        }
    }
    
    //--------------------------------------------------------------------------------

    func login(withUserName name:String,password:String) {
        QBRequest.logIn(withUserLogin: name, password: password, successBlock: { (response, user) in
            
        }) { (error) in
            
        }
    }
    
    //-----------------------------------------------------------------------
    
    func uploadFile(data: Data, contentType: String, success: ((QBCBlob) -> Void)?, failure: ((Error) -> Void)?) {
        
        QBRequest.tUploadFile(data, fileName: "ProfileImage", contentType: contentType, isPublic: true, successBlock: { (response, blob) in
            
            if success != nil {
                success!(blob)
            }
            
        }, statusBlock: { (request, status) in
            
        }, errorBlock: { (response) in
            
            if failure != nil, response.error?.error != nil {
                failure!((response.error?.error)!)
            }
        })
    }
    
    //-----------------------------------------------------------------------
    
    func logOut(success: ((Bool) -> Void)?, failure: ((Error) -> Void)?) {
        
        QBRequest.logOut(successBlock: { (response) in
            if success != nil {
                success!(response.isSuccess)
            }
        }) { (response) in
            if failure != nil, response.error?.error != nil {
                failure!((response.error?.error)!)
            }
        }
        self.logOutFromChat()
    }
    
    //-----------------------------------------------------------------------
    
    func createDialog(id: NSNumber, result: ((Bool) -> Void)?) {
        
        if currentUser != nil, case let currentUserID = NSNumber.init(value: (currentUser?.id)!) {
            let chatDialog = QBChatDialog(dialogID: "", type: .private)
            chatDialog.occupantIDs = [currentUserID, id]
            QBRequest.createDialog(chatDialog, successBlock: { (response, chatDialog) in
                self.currentChatDialog = chatDialog
                self.setUserWithChatMessages(id: UInt(id), result: { (bool) in
                    if result != nil {
                        result!(bool)
                    }
                    if self.delegate != nil, (self.delegate?.responds(to: #selector(QuickbloxManagerDelegate.reloadData)))! {
                        self.delegate?.reloadData!()
                    }
                })
            }) { (response) in
                if result != nil {
                    result!(false)
                }
                if self.delegate != nil, (self.delegate?.responds(to: #selector(QuickbloxManagerDelegate.reloadData)))! {
                    self.delegate?.reloadData!()
                }
            }
        }
    }
    
    //-----------------------------------------------------------------------
    
    func sendMessage(chatDialog: QBChatDialog?, message: String?, attachment: Data?, type: String,isForGroupChat:Bool, customParameters: [String: String], result: ((QBChatMessage?, Error?) -> Void)?) {
        
        if chatDialog != nil {
            
            if message != nil {
                
                sendChatMessage(chatDialog: chatDialog!, message: message, attachment: nil, isForGroupChat: isForGroupChat, customParameters: customParameters, result: { (chatMessage, error) in
                    if result != nil {
                        
                        var usersId:String
                        if isForGroupChat {
                            let stringOccupants = (chatDialog?.occupantIDs?.map {
                                $0.uintValue != self.currentUser?.id ? String(describing: $0) : nil
                                
                                })?.flatMap{$0}
                            
                            usersId  = stringOccupants!.joined(separator: ", ")

                        } else {
                             usersId = "\(chatDialog!.recipientID)"
                        }
                      
                        if !self.isFromCall {
                        //    AppDelegate.sharedInstance().sendQuickBloxPush(usersId, message: message!, opponentName: (self.currentUser?.fullName)!)
                        }
                        
                        result!(chatMessage, error)
                    }
                })
                
            } else if attachment != nil {
                
                var contentType = ""
                if customParameters["type"] == "image" {
                    contentType = "image/png"
                } else if customParameters["type"] == "video" {
                    contentType = "video/mp4"
                }
                
                uploadFile(data: attachment!, contentType: contentType, success: { (blob) in
                    
                    let chatAttachment = QBChatAttachment()
                    chatAttachment.type = type
                    chatAttachment.id = "\(blob.id)"
                    chatAttachment.url = blob.privateUrl()
                    self.sendChatMessage(chatDialog: chatDialog!, message: "Attachment", attachment: chatAttachment, isForGroupChat: isForGroupChat, customParameters: customParameters, result: { (chatMessage, error) in
                        if result != nil {
                            result!(chatMessage, error)
                        }
                    })
                    
                }, failure: { (error) in
                    if result != nil {
                        result!(nil, error)
                    }
                })
                
            } else {
                if result != nil {
                    let error = NSError(domain: "", code: 500, userInfo: [NSLocalizedDescriptionKey: "Content should not be empty"])
                    result!(nil, error)
                }
            }
            
        } else {
            if result != nil {
                let error = NSError(domain: "", code: 500, userInfo: [NSLocalizedDescriptionKey: "Chat Dialog is not available"])
                result!(nil, error)
            }
        }
    }
    
    //-----------------------------------------------------------------------

    func getMessageByDialogID(dialogID: String,forGroupChat:Bool, success: (([QBChatMessage]?) -> Void)?, failure: ((Error?) -> Void)?) {
        
        let extendedRequest = ["sort_desc" : "date_sent"]
        
        QBRequest.countOfMessages(forDialogID: dialogID, extendedRequest: extendedRequest, successBlock: { (response, count) in
            
            self.getMessagesByPaging(dialogID: dialogID, count: count, skip: 0,forGroupChat: forGroupChat, success: { (arrChatMessages) in
                
                
                if success != nil {
                    success!(arrChatMessages)
                }
                
                
                
            }, failure: { (error) in
                if failure != nil {
                    failure!(response.error?.error)
                }
            })
            
        }) { (response) in
            
            if failure != nil {
                failure!(response.error?.error)
            }
            
            if self.delegate != nil, (self.delegate?.responds(to: #selector(QuickbloxManagerDelegate.reloadData)))! {
                self.delegate?.reloadData!()
            }
        }
    }
    
    //-----------------------------------------------------------------------
    
    fileprivate func getMessagesByPaging(dialogID: String, count: UInt, skip: Int,forGroupChat:Bool, success: (([QBChatMessage]?) -> Void)?, failure: ((Error?) -> Void)?) {
        
        let responsePage = QBResponsePage()
        responsePage.limit = 100
        responsePage.skip = skip
        
        let extendedRequest = ["sort_desc" : "date_sent"]
        
        QBRequest.messages(withDialogID: dialogID, extendedRequest: extendedRequest, for: responsePage, successBlock: {(response: QBResponse, messages: [QBChatMessage]?, responcePage: QBResponsePage?) in
            
            
            if forGroupChat {
                // Beofre response comes if user press back button on Chat detail screen
                if self.selectedGroupChat.groupChatDialog?.id != nil &&  self.selectedGroupChat.groupChatDialog?.id == dialogID {
                    self.selectedGroupChat.arrGroupChatMessages += messages!
                    
                    //Append  User to array
                   messages?.enumerated().forEach({ (index,chatMessage) -> Void in
                    if chatMessage.senderID != self.currentUser?.id && !self.selectedGroupChat.arrGroupMembers.contains(NSNumber(value:chatMessage.senderID)) {
                        self.selectedGroupChat.arrGroupMembers.append(NSNumber(value: chatMessage.senderID))
                        let senderUsers = self.arrAllContacts.filter{$0.id == chatMessage.senderID}
                        self.selectedGroupChat.users += senderUsers
                    }
                   })
                    
                    self.updateGlobalArrayForGroupChat(userWithChatMessages: self.selectedGroupChat, updateProfileImage: false)

                    
                    if count > UInt(self.selectedGroupChat.arrGroupChatMessages.count) {
                        self.getMessagesByPaging(dialogID: dialogID, count: count, skip: self.selectedGroupChat.arrGroupChatMessages.count,forGroupChat: forGroupChat, success: nil, failure: nil)
                    }
                    
                }
                
            } else {
                
                if self.selectedUserWithChatMessages.chatDialog?.id != nil &&  self.selectedUserWithChatMessages.chatDialog?.id == dialogID {
                    
                    self.selectedUserWithChatMessages.arrChatMessages += messages!
                    self.updateGlobalArray(userWithChatMessages: self.selectedUserWithChatMessages, updateProfileImage: false)
                    
                    
                    if count > UInt(self.selectedUserWithChatMessages.arrChatMessages.count) {
                        self.getMessagesByPaging(dialogID: dialogID, count: count, skip: self.selectedUserWithChatMessages.arrChatMessages.count,forGroupChat: forGroupChat, success: nil, failure: nil)
                    }
                }
                
            }
            if success != nil {
                success!(messages)
            }
            
            if self.delegate != nil, (self.delegate?.responds(to: #selector(QuickbloxManagerDelegate.reloadData)))! {
                self.delegate?.reloadData!()
            }
            
            
        }, errorBlock: {(response: QBResponse!) in
            if failure != nil {
                failure!(response.error?.error)
            }
            if self.delegate != nil, (self.delegate?.responds(to: #selector(QuickbloxManagerDelegate.reloadData)))! {
                self.delegate?.reloadData!()
            }
        })
    }
    
    //-----------------------------------------------------------------------

    fileprivate func setUserWithChatMessages(id: UInt, result: ((Bool) -> Void)?) {
        
        if self.currentChatDialog != nil {
            
            self.selectedUserWithChatMessages.chatDialog = self.currentChatDialog
            
            QBRequest.user(withID: id, successBlock: { (response, user) in
                
                self.selectedUserWithChatMessages.user = user
                self.selectedUserWithChatMessages.arrChatMessages = []
                
                if result != nil {
                    result!(true)
                }
                
                if user.blobID != nil {
                    
                    self.downloadFile(id: UInt((user.blobID)), savePath: nil, success: { (image, savePath) in
                        
                        self.selectedUserWithChatMessages.profileImage = image
                        
                    }, failure: { (error) in
                        
                        self.selectedUserWithChatMessages.profileImage = nil
                    })
                    
                } else {
                    if result != nil {
                        result!(true)
                    }
                }
                
            }, errorBlock: { (response) in
                
                if result != nil {
                    result!(false)
                }
            })
        } else {
            
            if result != nil {
                result!(false)
            }
        }
    }
    
    //-----------------------------------------------------------------------
    
    func downloadFile(id: UInt, savePath: String?, success: ((UIImage?, String?) -> Void)?, failure: ((Error) -> Void)?) {
        
        QBRequest.backgroundDownloadFile(withID: id, successBlock: { (response, data) in
            
            //  if let image = UIImage(data: data) {
            if savePath != nil {
                let url = URL(fileURLWithPath: savePath!)
                do {
                    try data.write(to: url, options: .atomic)
                } catch {
                    print("error")
                }
                // let result = FileManager.default.createFile(atPath: savePath!, contents: data, attributes: nil)
                //  print(result)
            }
            
            if success != nil {
                if let image = UIImage(data: data) {
                    success!(image, savePath)
                } else {
                    success!(nil, savePath)
                }
            }
            
            //    } else {
            //  let error = NSError(domain: "", code: 500, userInfo: [NSLocalizedDescriptionKey: "Internal Error"])
            //   if failure != nil {
            //    failure!(error)
            //  }
            //}
        }, statusBlock: { (request, status) in
            
        }) { (response) in
            if failure != nil, let error = response.error?.error {
                failure!(error)
            }
        }
    }
    
    //-----------------------------------------------------------------------
    
    fileprivate func getUserByID(userID: UInt, success: ((QBUUser) -> Void)?, failure: ((Error) -> Void)?) {
        
        QBRequest.user(withID: userID, successBlock: { (response, user) in
            if success != nil {
                success!(user)
            }
        }) { (response) in
            if failure != nil, let error = response.error?.error {
                failure!(error)
            }
        }
    }
    
    //-----------------------------------------------------------------------
    
    fileprivate func updateArray(message: QBChatMessage, userWithChatMessages: ((UserWithChatMessages) -> Void)?) {
        
        if selectedUserWithChatMessages.user?.id == message.senderID {
            
            selectedUserWithChatMessages.arrChatMessages.insert(message, at: 0)
            selectedUserWithChatMessages.chatDialog?.lastMessageText = message.text
            
            updateGlobalArray(userWithChatMessages: selectedUserWithChatMessages, updateProfileImage: false)
            if userWithChatMessages != nil {
                userWithChatMessages!(selectedUserWithChatMessages)
            }
            
        } else {
            
            if let index = self.arrUsersWithChatMessages.index(where:  { (user) -> Bool in
                return user.user?.id == message.senderID
                
            }) {
                var user = self.arrUsersWithChatMessages[index]
                user.arrChatMessages.insert(message, at: 0)
                user.chatDialog?.lastMessageText = message.text
                user.chatDialog?.unreadMessagesCount += 1
                self.arrUsersWithChatMessages.remove(at: index)
                self.arrUsersWithChatMessages.insert(user, at: 0)

                if userWithChatMessages != nil {
                    userWithChatMessages!(self.arrUsersWithChatMessages[0])
                }
                
            } else {
                
                var userWithChatMessagesTemp = UserWithChatMessages(user: nil, arrChatMessages: [message], chatDialog: nil, profileImage: nil)

                let responsePage = QBResponsePage()
                let extendedRequest: [String : String] = ["_id": message.dialogID!]
                
                QBRequest.dialogs(for: responsePage, extendedRequest: extendedRequest, successBlock: { (response, arrChatDialogs, dialogsUsersIDs, responsePage) in
                    
                    if (arrChatDialogs.count) > 0 {
                        let chatDialog = arrChatDialogs[0]
                        userWithChatMessagesTemp.chatDialog = chatDialog
                        userWithChatMessagesTemp.chatDialog?.lastMessageText = message.text
                        userWithChatMessagesTemp.chatDialog?.unreadMessagesCount += 1
                    }
                    
                    self.getUserByID(userID: message.senderID, success: { (user) in
                        
                        userWithChatMessagesTemp.user = user
                        self.updateGlobalArray(userWithChatMessages: userWithChatMessagesTemp, updateProfileImage: false)
                        
                        if userWithChatMessages != nil {
                            userWithChatMessages!(userWithChatMessagesTemp)
                        }
                        
                        self.downloadFile(id: UInt(user.blobID), savePath: "", success: { (image, savePath) in
                            
                            userWithChatMessagesTemp.profileImage = image
                            self.updateGlobalArray(userWithChatMessages: userWithChatMessagesTemp, updateProfileImage: true)
                            
                        }, failure: { (error) in
                            
                        })
                        
                    }, failure: { (error) in
                        
                    })
                    
                }) { (response) in
                    
                    if userWithChatMessages != nil {
                        userWithChatMessages!(userWithChatMessagesTemp)
                    }
                }
            }
        }
    }
    
    //-----------------------------------------------------------------------
    
    fileprivate func updateGlobalArray(userWithChatMessages: UserWithChatMessages, updateProfileImage: Bool) {
        
        if let index = self.arrUsersWithChatMessages.index(where:  { (userWithChatMessagesTemp) -> Bool in
            
            return userWithChatMessagesTemp.user?.id == userWithChatMessages.user?.id
            
        }) {
            
            if (updateProfileImage) {
                self.arrUsersWithChatMessages[index] = userWithChatMessages
            } else {
                self.arrUsersWithChatMessages.remove(at: index)
                self.arrUsersWithChatMessages.insert(userWithChatMessages, at: 0)
            }
            
        } else {
            self.arrUsersWithChatMessages.insert(userWithChatMessages, at: 0)
        }
        
        if self.arrUsersWithChatMessages.count > 1 {
            self.arrUsersWithChatMessages.sort { (user1, user2) -> Bool in
                if user1.chatDialog != nil, ((user1.chatDialog?.lastMessageDate) != nil), user2.chatDialog != nil, ((user2.chatDialog?.lastMessageDate) != nil) {
                    return (user1.chatDialog?.lastMessageDate)! > (user2.chatDialog?.lastMessageDate)!
                }
                return true
            }
        }
    }
    
    //-----------------------------------------------------------------------

//    func getUnReadMessageCount(dialogsIDs: Set<String>) {
//        
////        let dialogsIDs = dialogsIDs
////        QBRequest.totalUnreadMessageCountForDialogs(withIDs: dialogsIDs, successBlock: { (response, count, dictionary) in
////            
////        }) { (response) in
////            
////        }
//    }
//    
//    //-----------------------------------------------------------------------
//    
//    func delete(arrIDs: Set<String>) {
//        
//        QBRequest.deleteMessages(withIDs: arrIDs, forAllUsers: <#T##Bool#>, successBlock: <#T##((QBResponse) -> Void)?##((QBResponse) -> Void)?##(QBResponse) -> Void#>, errorBlock: QBRequestErrorBlock?)
//    }
    
    //-----------------------------------------------------------------------
    
    func resizedImage(from image: UIImage) -> UIImage {
        
        let largestSide: CGFloat = image.size.width > image.size.height ? image.size.width : image.size.height
        let scaleCoefficient: CGFloat = largestSide / 560.0
        let newSize = CGSize(width: image.size.width / scaleCoefficient, height: image.size.height / scaleCoefficient)
        UIGraphicsBeginImageContext(newSize)
        image.draw(in: CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return resizedImage!
    }
}

//-----------------------------------------------------------------------

// MARK: - Extension: Audio Call Methods

//-----------------------------------------------------------------------

extension QuickbloxManager {
    
    //-----------------------------------------------------------------------
    
    func startAudioCall(arrIDs: [NSNumber], userInfo: [String: String]?) {
        
        sessionForAudioVideoCall = QBRTCClient.instance().createNewSession(withOpponents: arrIDs, with: .audio)
        sessionForAudioVideoCall?.startCall(userInfo)
    }
    
    //-----------------------------------------------------------------------

    func startTimer() {
        
        if timer != nil {
            timer?.invalidate()
            timer = nil
        }
        
        timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(updateCallTime(timer:)), userInfo: nil, repeats: true)
        timer?.fire()
    }
    
    //-----------------------------------------------------------------------

    @objc func updateCallTime(timer: Timer) {
        
//        print("updateCallTime called")
//        callTimeInterval += 1
//
//        if MenuBaseViewController.sharedInstance().currentViewController() is ChatAudioVideoVC {
//
//            let hours = Int(callTimeInterval) / 3600
//            let minutes = Int(callTimeInterval) / 60 % 60
//            let seconds = Int(callTimeInterval) % 60
//
//            strCallTime = String(format: "%02i:%02i:%02i", hours, minutes, seconds)
//            DispatchQueue.main.async {
//                (MenuBaseViewController.sharedInstance().currentViewController() as! ChatAudioVideoVC).updateCallTime(strCallTime: self.strCallTime)
//            }
//        }
    }
    
    //-----------------------------------------------------------------------

    func sendCallMessage(_ session: QBRTCSession) {
        
        if currentUser != nil {
            if session.initiatorID == NSNumber(value: (currentUser?.id)!), selectedUserWithChatMessages.chatDialog != nil {
                
                let message = "Call notification: \(strCallTime)"
                sendMessage(chatDialog: selectedUserWithChatMessages.chatDialog, message: message, attachment: nil, type: "text", isForGroupChat: false, customParameters: ["type": "text"], result: { (chatMessage, error) in
                    if self.delegate != nil, (self.delegate?.responds(to: #selector(QuickbloxManagerDelegate.reloadData)))! {
                        self.delegate?.reloadData!()
                    }
                })
            }
        }
    }
    
    //-----------------------------------------------------------------------
}

//-----------------------------------------------------------------------

// MARK: - Extension: File Private Methods

//-----------------------------------------------------------------------

extension QuickbloxManager {
    
    //-----------------------------------------------------------------------
    
    fileprivate func uploadUserProfileImage(strURL: String) {
        
        DispatchQueue.global().async {
            if let url = URL(string: strURL) {
                do {
                    let data = try Data.init(contentsOf: url)
                    self.uploadFile(data: data, contentType: "image/png", success: { (blob) in
                        let updateUserParameters = QBUpdateUserParameters()
                        updateUserParameters.blobID = blob.id
                        QBRequest.updateCurrentUser(updateUserParameters, successBlock: { (response, user) in
                            self.currentUser = user
                        }, errorBlock: { (response) in
                            
                        })
                    }, failure: { (error) in
                        
                    })
                } catch {
                }
            }
        }
    }
    
    //-----------------------------------------------------------------------

    fileprivate func logInWithChat() {
        
        if currentUser != nil {
            
            let user = QBUUser()
            user.id = (currentUser?.id)!
            user.password = kQuickBloxPassword.base64Decoded()
            
            QBChat.instance.addDelegate(self)
            QBChat.instance.connect(with: user, completion: { (error) in
                
                QBRTCClient.initializeRTC()
                QBRTCClient.instance().add(self)
                QBRTCConfig.setAnswerTimeInterval(60)
                
                self.setUsersWithChatMessages()
                self.setGroupUsersWithChatMessages()
                self.getAllUsers(pageNo: 1, success: nil, failure: nil)
            })
        }
    }
    
    //-----------------------------------------------------------------------
    
    fileprivate func logOutFromChat() {
        if QBChat.instance.isConnected {
            QBChat.instance.disconnect(completionBlock: { (error) in
                self.removeAllData = true
            })
        }
    }
    
    //-----------------------------------------------------------------------
    
    fileprivate func getAllUsers(pageNo: UInt, success: (([QBUUser]?) -> Void)?, failure: ((Error?) -> Void)?) {
        
        let generalResponsePage = QBGeneralResponsePage(currentPage: pageNo, perPage: 100)
        
        QBRequest.users(for: generalResponsePage, successBlock: { (response, responsePage, arrUsers) in
            
            if arrUsers != nil {
                var arrUsersTemp = arrUsers
                if let index = arrUsersTemp.index(where: { (user) -> Bool in
                    return user.id == self.currentUser?.id
                }) {
                    arrUsersTemp.remove(at: index)
                }
                
                self.arrAllContacts += arrUsersTemp
            }
            
            self.arrSearchContacts = self.arrAllContacts
            
            if success != nil {
                success!(arrUsers)
            }
            
            if self.delegate != nil, (self.delegate?.responds(to: #selector(QuickbloxManagerDelegate.reloadData)))! {
                self.delegate?.reloadData!()
            }
            
            if (responsePage.totalEntries) > UInt(self.arrAllContacts.count + 1) {
                self.getAllUsers(pageNo: pageNo + 1, success: nil, failure: nil)
            }
            
        }) { (response) in
            if failure != nil {
                failure!(response.error?.error)
            }
            
            if self.delegate != nil, (self.delegate?.responds(to: #selector(QuickbloxManagerDelegate.reloadData)))! {
                self.delegate?.reloadData!()
            }
        }
    }
    
    //-----------------------------------------------------------------------
    
    fileprivate func sendChatMessage(chatDialog: QBChatDialog, message: String?, attachment: QBChatAttachment?,isForGroupChat:Bool, customParameters: [String: String], result: ((QBChatMessage, Error?) -> Void)?) {
        
        let chatMessage = QBChatMessage.markable()
        chatMessage.customParameters = NSMutableDictionary.init(dictionary: customParameters)
        
        if currentUser != nil {
            chatMessage.senderID = (currentUser?.id)!
        }
        if message != nil {
            chatMessage.text = message
        }
        
        chatMessage.customParameters.setValue(true, forKey: "save_to_history")
        if attachment != nil {
            chatMessage.attachments = [attachment!]
        }
        
        chatDialog.send(chatMessage, completionBlock: { (error) in
            if isForGroupChat == false {
                self.selectedUserWithChatMessages.arrChatMessages.insert(chatMessage, at: 0)
                self.selectedUserWithChatMessages.chatDialog?.lastMessageText = chatMessage.text
                self.selectedUserWithChatMessages.chatDialog?.lastMessageDate = chatMessage.dateSent
                self.updateGlobalArray(userWithChatMessages: self.selectedUserWithChatMessages, updateProfileImage: false)
            }
           
            if result != nil {
                result!(chatMessage, error)
            }
        })
    }
    
    //-----------------------------------------------------------------------
    
    fileprivate func getDialogs(count: UInt, skip: Int) {
        
        let extendedRequest = [
            "sort_desc": "last_message_date_sent",
            "type": "3"
        ]
        
        let responsePage = QBResponsePage()
        responsePage.limit = 50
        responsePage.skip = skip
        
        QBRequest.dialogs(for: responsePage, extendedRequest: extendedRequest, successBlock: { (response: QBResponse, dialogs: [QBChatDialog]?, dialogsUsersIDs: Set<NSNumber>?, page: QBResponsePage?) -> Void in
            
            if dialogs != nil, (dialogs?.count)! > 0 {
                
                for i in 0..<dialogs!.count {
                    
                    let arrIDs = dialogs?[i].occupantIDs?.filter { $0 != NSNumber.init(value: (self.currentUser?.id)!) }
                    if (arrIDs?.count)! > 0 {
                        let id = arrIDs?[0]
                        
                        QBRequest.user(withID: UInt(id!), successBlock: { (response, user) in
                            
                            var userWithChatMessages = UserWithChatMessages(user: user, arrChatMessages: [], chatDialog: dialogs?[i], profileImage: nil)
                            self.updateGlobalArray(userWithChatMessages: userWithChatMessages, updateProfileImage: false)
                            
                            if i == (dialogs?.count)! - 1 {
                                if self.delegate != nil, (self.delegate?.responds(to: #selector(QuickbloxManagerDelegate.reloadData)))! {
                                    self.delegate?.reloadData!()
                                }
                                if count > UInt(self.arrUsersWithChatMessages.count) {
                                    self.getDialogs(count: count, skip: self.arrUsersWithChatMessages.count)
                                } else {
                                   // QBChat.instance().addDelegate(self)
                                }
                            }
                            
                            if user.blobID != nil {
                                
                                self.downloadFile(id: UInt((user.blobID)), savePath: "", success: { (image, savePath) in
                                    
                                    userWithChatMessages.profileImage = image
                                    self.updateGlobalArray(userWithChatMessages: userWithChatMessages, updateProfileImage: true)
                                    
                                }, failure: { (error) in
                                    
                                })
                                
                            } else {
                                
                            }
                            
                        }, errorBlock: { (response) in
                            
                        })
                    }
                }
                
            } else {
               // QBChat.instance().addDelegate(self)
                if self.delegate != nil, (self.delegate?.responds(to: #selector(QuickbloxManagerDelegate.reloadData)))! {
                    self.delegate?.reloadData!()
                }
            }
            
        }) { (response: QBResponse) -> Void in
          //  QBChat.instance().addDelegate(self)
            if self.delegate != nil, (self.delegate?.responds(to: #selector(QuickbloxManagerDelegate.reloadData)))! {
                self.delegate?.reloadData!()
            }
        }
    }
    
    //-----------------------------------------------------------------------
    
    fileprivate func setUsersWithChatMessages() {
        
        let extendedRequest = [
            "sort_desc": "last_message_date_sent",
            "type": "3"
        ]
        
        QBRequest.countOfDialogs(withExtendedRequest: extendedRequest, successBlock: { (response, count) in
            
            self.getDialogs(count: count, skip: 0)
            
        }) { (response) in
            
        }
    }
    
    //-----------------------------------------------------------------------
}

//-----------------------------------------------------------------------

// MARK: - Extension: Group Create, Fetch GroupName  Methods

//-----------------------------------------------------------------------

extension QuickbloxManager {
    
    //-----------------------------------------------------------------------
    
    // MARK: - Group Methods
    
    //-----------------------------------------------------------------------
    
    func createGroupChatDialog(ids:[NSNumber],groupName : String,groupProfile:UIImage?, result: ((Bool,QBChatDialog?) -> Void)?) {
        
        if currentUser != nil, case let currentUserID = NSNumber.init(value: (currentUser?.id)!) {
            let chatDialog = QBChatDialog(dialogID: "", type: .group)
            var arrIds = ids
            arrIds.append(currentUserID)
            chatDialog.occupantIDs = arrIds
            chatDialog.name = groupName
            
            QBRequest.createDialog(chatDialog, successBlock: { (response, chatDialog) in
                self.currentGroupChatDialog = chatDialog
                
                
                //Upload the photo
                if let image = groupProfile {
                    self.uploadGroupProfile(image: image, chatDialog: chatDialog)
                    
                }
                
                QBRequest.users(withIDs: arrIds.map{$0.stringValue}, page: nil, successBlock: { (response, page, listOfUsers) in
                    
                    if chatDialog.isJoined() == false {
                        self.joinGroup(dialog: chatDialog, completion: { (error) in
                       //     Logger.println(object: "Group Join Error \(String(describing: error))")
                        })
                    }
                    
              /*      if (  self.arrGroupUsersWithChatMessages.contains(where: { (object) -> Bool in
                        (object.groupChatDialog?.id ?? "") == (chatDialog?.id ?? "")
                    }) == false) {
                        self.arrGroupUsersWithChatMessages.append(UserWithGroupChatMessages(arrGroupChatMessages: [], groupChatDialog: chatDialog, profileImage: nil, groupName: (chatDialog?.name!), arrGroupMembers: (chatDialog?.occupantIDs)!,imageDownloadBlobID:chatDialog?.photo,users:listOfUsers!))
                    }*/
                    
                  //  self.arrGroupUsersWithChatMessagesSearch = self.arrGroupUsersWithChatMessages
                    result!(true,chatDialog)
                    
                    
                }, errorBlock: { (response) in
                    
                })
                
                
                //Send Invitation To User
                chatDialog.occupantIDs?.forEach({ (occupantID) in
                    
                    let inviteMessage: QBChatMessage = self.createChatNotificationForGroupChatUpdate(dialog: chatDialog)
                    inviteMessage.recipientID = UInt(occupantID.intValue)
                    QBChat.instance.sendSystemMessage(inviteMessage, completion: { (ErrorInvite) in
                        if (ErrorInvite != nil) {
                         //   Logger.println(object:ErrorInvite)
                            
                        } else {
                         //   Logger.println(object:"Success")
                            
                            
                            
                        }
                        
                    })
                })
                
            }) { (response) in
                if result != nil {
                    result!(false,nil)
                }
            }
        }
    }
    
    //-----------------------------------------------------------------------
    
    func uploadGroupProfile(image : UIImage, chatDialog:QBChatDialog)  {
        
        DispatchQueue.global().async {
            let data =  UIImageJPEGRepresentation(image, 0.1)
            QBRequest.tUploadFile(data!, fileName: chatDialog.name!, contentType: "image/jpeg", isPublic: true, successBlock: { (response, uploadedBlob) in
                
                let uploadedFileID: UInt = uploadedBlob.id
                chatDialog.photo = "\(uploadedBlob.id)"
                
                QBRequest.update(chatDialog, successBlock: {(responce: QBResponse?, dialog: QBChatDialog?) in
                    print("Dialog updated")
                    
                    if let index =  self.arrGroupUsersWithChatMessages.index(where: {($0.groupChatDialog?.id ?? "") == (chatDialog.id ?? "") }) {
                        
                        var object = self.arrGroupUsersWithChatMessages[index];
                        object.imageDownloadBlobID = chatDialog.photo;
                        self.arrGroupUsersWithChatMessages[index] = object;
                        
                    //    self.arrGroupUsersWithChatMessagesSearch = self.arrGroupUsersWithChatMessages
                    }
                    
                    
                    
                    
                }, errorBlock: {(response: QBResponse!) in
                    print("error \(response.error)")
                })
                
            }, statusBlock: { (qbRequest, qbrequestStatus) in
                
            }, errorBlock: { (reponseError) in
              //  Logger.println(object: reponseError)
            })
            
        }
    }
    
    //-----------------------------------------------------------------------
    
    func joinGroup(dialog:QBChatDialog, completion :@escaping QBChatCompletionBlock) {
        if !dialog.isJoined() {
            
            dialog.join(completionBlock: completion)
        }
    }
    
    //-----------------------------------------------------------------------
    
    func leaveGroup(dialog:QBChatDialog, completion :@escaping ((QBError?) -> Swift.Void))  {
        
        let dialogGroup = dialog
        
        dialogGroup.pullOccupantsIDs = ["\(self.currentUser!.id)"]
        
        
        QBRequest.update(dialogGroup, successBlock: { (response, chatDialog) in
            completion(nil)
            let inviteMessage: QBChatMessage = self.createChatNotificationForGroupChatUpdate(dialog: chatDialog)
            
            chatDialog.occupantIDs?.forEach({ (occupantID) in
                
                let inviteMessage: QBChatMessage = self.createChatNotificationForGroupChatUpdate(dialog: chatDialog)
                inviteMessage.recipientID = UInt(occupantID.intValue)
                QBChat.instance.sendSystemMessage(inviteMessage, completion: { (ErrorInvite) in
                    if (ErrorInvite != nil) {
                     //   Logger.println(object:ErrorInvite)
                        
                    } else {
                    //    Logger.println(object:"Success")
                        
                        
                        
                    }
                    
                })
            })
            
        }) { (error) in
            completion(error.error)
        }
        
        
    }
    
    //-----------------------------------------------------------------------
    
    fileprivate func createChatNotificationForGroupChatUpdate(dialog: QBChatDialog) -> QBChatMessage {
        
        let inviteMessage: QBChatMessage = QBChatMessage()
        
        inviteMessage.text = "optional text"
        
        let customParams: NSMutableDictionary = NSMutableDictionary()
        customParams["xmpp_room_jid"] = dialog.roomJID
        customParams["name"] = dialog.name
        customParams["_id"] = dialog.id
        customParams["type"] = dialog.type.rawValue
        customParams["lastMessageDate"] = dialog.createdAt
        
        let stringOccupants = dialog.occupantIDs?.map {
            String(describing: $0)
        }
        customParams["occupants_ids"] = stringOccupants!.joined(separator: ", ")
        
        customParams["notification_type"] = "1"
        inviteMessage.customParameters = customParams
        return inviteMessage
    }
    
    //-----------------------------------------------------------------------
    
    func setGroupUsersWithChatMessages() {
        
        
        let extendedRequest = [
            "sort_desc": "last_message_date_sent",
            "type": "2"
        ]
        
        QBRequest.countOfDialogs(withExtendedRequest: extendedRequest, successBlock: { (response, count) in
            
            self.getDialogsGroup(count: count, skip: 0)
            
        }) { (response) in
            
        }
        
    }
    
    //------------------------------------------------------------
    
    fileprivate func getDialogsGroup(count: UInt, skip: Int) {
        
        let extendedRequest = [
            "sort_desc": "last_message_date_sent",
            "type[in]": "1,2"
        ]
        
        let responsePage = QBResponsePage()
        responsePage.limit = 50
        responsePage.skip = skip
        
        
        QBRequest.dialogs(for: responsePage, extendedRequest: extendedRequest, successBlock: { (response: QBResponse, dialogs: [QBChatDialog]?, dialogsUsersIDs: Set<NSNumber>?, page: QBResponsePage?) -> Void in
            
            if dialogs != nil, (dialogs?.count)! > 0 {
                
                // self.arrGroupUsersWithChatMessages.removeAll()
                
                dialogs?.enumerated().forEach({ (index, chatDialog) in
                    // Private group
                    let arrIDs = chatDialog.occupantIDs?.filter { $0 != NSNumber.init(value: (self.currentUser?.id)!) }
                    if (arrIDs?.count)! > 0 {
                        //let id = arrIDs?[0]
                        //   let resPage = QBResponsePage()
                        // QBRequest.messages(withDialogID: (dialogs?[index].id)!, extendedRequest: nil, for: resPage, successBlock: {(response: QBResponse, messages: [QBChatMessage]?, responcePage: QBResponsePage?) in
                        //   if messages != nil {
                        //chatDialog.photo
                       
                        QBRequest.users(withIDs: (dialogs?[index].occupantIDs!.map{$0.stringValue})!, page: nil, successBlock: { (response, page, listOfUsers) in
                            if chatDialog.isJoined() == false {
                                //
                                self.joinGroup(dialog: chatDialog, completion: { (error) in
                                    //   Logger.println(object: "Group Join Error \(String(describing: error))")
                                })
                            }
                            
                            if (  self.arrGroupUsersWithChatMessages.contains(where: { (object) -> Bool in
                                (object.groupChatDialog?.id ?? "") == (chatDialog.id ?? "")
                            }) == false) {
                                self.arrGroupUsersWithChatMessages.append(UserWithGroupChatMessages(arrGroupChatMessages: [], groupChatDialog: chatDialog, profileImage: nil, groupName: (dialogs?[index].name!), arrGroupMembers: (dialogs?[index].occupantIDs)!,imageDownloadBlobID:dialogs?[index].photo,users:listOfUsers))
                                //   self.arrGroupUsersWithChatMessagesSearch = self.arrGroupUsersWithChatMessages
                                
                            }
                            
                            if index == (dialogs?.count)! - 1 {
                                if self.delegate != nil, (self.delegate?.responds(to: #selector(QuickbloxManagerDelegate.reloadData)))! {
                                    self.delegate?.reloadData!()
                                    
                                }
                                if count > UInt(self.arrGroupUsersWithChatMessages.count) {
                                    self.getDialogsGroup(count: count, skip: self.arrGroupUsersWithChatMessages.count)
                                } else {
                                    QBChat.instance.addDelegate(self)
                                    
                                }
                            }
                            
                        }, errorBlock: { (response) in
                            
                        })
                        

                        
                    } else {
                        
                        
                        QBChat.instance.addDelegate(self)
                        
                        // In case of Public Group
                        if chatDialog.isJoined() == false {
                            
                            self.joinGroup(dialog: chatDialog, completion: { (error) in
                                //   Logger.println(object: "Group Join Error \(String(describing: error))")
                            })
                        }
                        
                        if (  self.arrGroupUsersWithChatMessages.contains(where: { (object) -> Bool in
                            (object.groupChatDialog?.id ?? "") == (chatDialog.id ?? "")
                        }) == false) {
                            self.arrGroupUsersWithChatMessages.append(UserWithGroupChatMessages(arrGroupChatMessages: [], groupChatDialog: chatDialog, profileImage: nil, groupName: (dialogs?[index].name!), arrGroupMembers: (dialogs?[index].occupantIDs)!,imageDownloadBlobID:dialogs?[index].photo,users:[]))
                            //   self.arrGroupUsersWithChatMessagesSearch = self.arrGroupUsersWithChatMessages
                            
                        }
                        
                    }
                    
                    
                })
                
            } else {
                QBChat.instance.addDelegate(self)
                
                if self.delegate != nil, (self.delegate?.responds(to: #selector(QuickbloxManagerDelegate.reloadData)))! {
                    self.delegate?.reloadData!()
                }
            }
        }) { (response: QBResponse) -> Void in
            QBChat.instance.addDelegate(self)
            
            if self.delegate != nil, (self.delegate?.responds(to: #selector(QuickbloxManagerDelegate.reloadData)))! {
                self.delegate?.reloadData!()
            }
        }
        
    }
    
    //------------------------------------------------------------
    
    func updateArrayGroupArrayOnNewMessage(message: QBChatMessage,fromDialogID dialogID: String, userWithChatMessages: ((UserWithGroupChatMessages) -> Void)?) {
        
        
        
        //        let sender = QuickbloxManager.sharedManager.selectedGroupChat.arrGroupMembers.filter({ $0.uintValue != QuickbloxManager.sharedManager.currentUser?.id && $0.uintValue ==  message.senderID })
        
        if QuickbloxManager.sharedManager.selectedGroupChat.groupChatDialog?.id == dialogID  {
            
            guard (selectedGroupChat.arrGroupChatMessages.filter{ $0.id == message.id}).count == 0 else {
                return
            }
            self.selectedGroupChat.groupChatDialog?.lastMessageText = message.text
            self.selectedGroupChat.groupChatDialog?.lastMessageDate = message.dateSent
            
            selectedGroupChat.arrGroupChatMessages.insert(message, at: 0)
            
            if message.senderID != self.currentUser?.id && !self.selectedGroupChat.arrGroupMembers.contains(NSNumber(value:message.senderID)) {
                self.selectedGroupChat.arrGroupMembers.append(NSNumber(value: message.senderID))
                let senderUsers = self.arrAllContacts.filter{$0.id == message.senderID}
                self.selectedGroupChat.users += senderUsers
            }

            
            updateGlobalArrayForGroupChat(userWithChatMessages: selectedGroupChat, updateProfileImage: false)
            if userWithChatMessages != nil {
                userWithChatMessages!(selectedGroupChat)
            }
            
            //This is required to mark read
            QBChat.instance.read(message, completion: { (error) in
                
            })
            
        } else {
            
            if let index = self.arrGroupUsersWithChatMessages.index(where:  { (user) -> Bool in
                return user.groupChatDialog?.id == dialogID
                
            }) {
                
                guard (self.arrGroupUsersWithChatMessages[index].arrGroupChatMessages.filter{ $0.id == message.id}).count == 0 else {
                    return
                }
                
                var user = self.arrGroupUsersWithChatMessages[index]
                user.arrGroupChatMessages.insert(message, at: 0)
                user.groupChatDialog?.lastMessageText = message.text
                user.groupChatDialog?.unreadMessagesCount += 1
                self.arrGroupUsersWithChatMessages.remove(at: index)
                self.arrGroupUsersWithChatMessages.insert(user, at: 0)
                
                if message.senderID != self.currentUser?.id && !self.arrGroupUsersWithChatMessages[index].arrGroupMembers.contains(NSNumber(value:message.senderID)) {
                    self.arrGroupUsersWithChatMessages[index].arrGroupMembers.append(NSNumber(value: message.senderID))
                    let senderUsers = self.arrAllContacts.filter{$0.id == message.senderID}
                    self.arrGroupUsersWithChatMessages[index].users += senderUsers
                }

                
                self.arrGroupUsersWithChatMessages[index].groupChatDialog?.lastMessageText = message.text
                self.arrGroupUsersWithChatMessages[index].groupChatDialog?.lastMessageDate = message.dateSent
                
                // self.arrGroupUsersWithChatMessages[index].arrGroupChatMessages.insert(message, at: 0)
                // updateGlobalArrayForGroupChat(userWithChatMessages: self.arrGroupUsersWithChatMessages[index], updateProfileImage: false)
                
               // self.arrGroupUsersWithChatMessagesSearch = self.arrGroupUsersWithChatMessages
                // arrGroupUsersWithChatMessages = arrGroupUsersWithChatMessagesSearch
                
                if userWithChatMessages != nil {
                    userWithChatMessages!(self.arrGroupUsersWithChatMessages[index])
                }
                
                
                
                
                
            } else {
                //TODO: PENDING TO DO
                
                var userWithChatMessagesTemp = UserWithGroupChatMessages( arrGroupChatMessages: [message], groupChatDialog: nil, profileImage: nil,groupName:nil,arrGroupMembers:[],imageDownloadBlobID:nil,users:[])
                
                let responsePage = QBResponsePage()
                let extendedRequest: [String : String] = ["_id": message.dialogID!]
                
                QBRequest.dialogs(for: responsePage, extendedRequest: extendedRequest, successBlock: { (response, arrChatDialogs, dialogsUsersIDs, responsePage) in
                    
                    for  var (index, chatDialog)  in  arrChatDialogs.enumerated() {
                        
                        // if (arrChatDialogs?.count)! > 0 {
                        
                        //  }
                        //
                        
                      
                        
                        QBRequest.users(withIDs: (arrChatDialogs[index].occupantIDs!.map{$0.stringValue}), page: nil, successBlock: { (response, page, listOfUsers) in
                            if chatDialog.isJoined() == false {
                                
                                self.joinGroup(dialog: chatDialog, completion: { (error) in
                                    //   Logger.println(object: "Group Join Error \(String(describing: error))")
                                })
                            }
                            
                            if (  self.arrGroupUsersWithChatMessages.contains(where: { (object) -> Bool in
                                (object.groupChatDialog?.id ?? "") == (chatDialog.id ?? "")
                            }) == false) {
                                
                                let chatDialog = arrChatDialogs[index]
                                userWithChatMessagesTemp.groupChatDialog = chatDialog
                                userWithChatMessagesTemp.groupChatDialog?.lastMessageText = message.text
                                userWithChatMessagesTemp.groupChatDialog?.unreadMessagesCount += 1
                                userWithChatMessagesTemp.groupName = chatDialog.name
                                userWithChatMessagesTemp.arrGroupMembers = (chatDialog.occupantIDs!)
                                userWithChatMessagesTemp.imageDownloadBlobID = chatDialog.photo
                                userWithChatMessagesTemp.users = listOfUsers
                                
                                
                                
                                self.arrGroupUsersWithChatMessages.append(userWithChatMessagesTemp)
                                
                                //    self.arrGroupUsersWithChatMessagesSearch = self.arrGroupUsersWithChatMessages
                                
                                if userWithChatMessages != nil {
                                    userWithChatMessages!(self.arrGroupUsersWithChatMessages[index])
                                }
                                
                                
                            }
                        } , errorBlock: { (response) in
                                
                            })
                        
                    
                        
                    }
                }) { (response) in
                    
                    if userWithChatMessages != nil {
                        userWithChatMessages!(userWithChatMessagesTemp)
                    }
                }
                
            }
        }
    }
    
    //------------------------------------------------------------
    
    func updateGlobalArrayForGroupChat(userWithChatMessages: UserWithGroupChatMessages, updateProfileImage: Bool) {
        
        if let index = self.arrGroupUsersWithChatMessages.index(where:  { (userWithChatMessagesTemp) -> Bool in
            
            return (userWithChatMessagesTemp.groupChatDialog?.id ?? "") == (userWithChatMessages.groupChatDialog? .id ?? "")
            
        }) {
            
            if (updateProfileImage) {
                self.arrGroupUsersWithChatMessages[index] = userWithChatMessages
            } else {
                self.arrGroupUsersWithChatMessages.remove(at: index)
                self.arrGroupUsersWithChatMessages.insert(userWithChatMessages, at: 0)
            }
            
        } else {
            self.arrGroupUsersWithChatMessages.insert(userWithChatMessages, at: 0)
        }
        
        if self.arrGroupUsersWithChatMessages.count > 1 {
            self.arrGroupUsersWithChatMessages.sort { (user1, user2) -> Bool in
                
                if user1.groupChatDialog != nil, ((user1.groupChatDialog?.lastMessageDate) != nil), user2.groupChatDialog != nil, ((user2.groupChatDialog?.lastMessageDate) != nil) {
                    return (user1.groupChatDialog?.lastMessageDate)! > (user2.groupChatDialog?.lastMessageDate)!
                } else if user1.groupChatDialog != nil, ((user1.groupChatDialog?.updatedAt) != nil), user2.groupChatDialog != nil, ((user2.groupChatDialog?.updatedAt) != nil){
                    return (user1.groupChatDialog?.updatedAt)! > (user2.groupChatDialog?.updatedAt)!
                    
                }
                return true
            }
        }
        
      //  arrGroupUsersWithChatMessagesSearch = arrGroupUsersWithChatMessages
        
    }

    
    //-----------------------------------------------------------------------
}

//-----------------------------------------------------------------------

// MARK: - Extension: QBChatDelegate

//-----------------------------------------------------------------------

extension QuickbloxManager: QBChatDelegate {
    
    //-----------------------------------------------------------------------

    public func chatDidReceive(_ message: QBChatMessage) {
        
        updateArray(message: message) { (userWithChatMessages) in
            if self.delegate != nil, (self.delegate?.responds(to: #selector(QuickbloxManagerDelegate.chatReceive(_:))))! {
                self.delegate?.chatReceive!(message)
            }
        }
    }
    
    //-----------------------------------------------------------------------

    public func chatDidReceiveSystemMessage(_ message: QBChatMessage) {
       // Logger.println(object: "chatDidReceiveSystemMessage")
        
        if let customParameters = message.customParameters as? [String:Any],let type = customParameters["type"] as? String,let id = customParameters["_id"] as? String {
            if type == "2" {
                message.dialogID = id
                message.markable = true
                message.text = ""
                
                self.updateArrayGroupArrayOnNewMessage(message: message,fromDialogID: id) { (groupMessageSelected) in
                    
                    if let index = self.arrGroupUsersWithChatMessages.index(where:  { (user) -> Bool in
                        return user.groupChatDialog?.id == id
                        
                    }) {
                        var userObj = self.arrGroupUsersWithChatMessages[index]
                        userObj.arrGroupChatMessages = []
                        userObj.groupChatDialog?.unreadMessagesCount = 0
                        userObj.groupChatDialog?.lastMessageText = "New Group"
                        userObj.groupChatDialog?.lastMessageDate = customParameters["lastMessageDate"] as? Date
                        self.arrGroupUsersWithChatMessages.remove(at: index)
                        
                        self.arrGroupUsersWithChatMessages.insert(userObj, at: 0)
                        
                    }
                    
                    
                    if self.delegate != nil, (self.delegate?.responds(to: #selector(QuickbloxManagerDelegate.chatReceive(_:))))! {
                        self.delegate?.chatReceive!(message)
                    }
                }
            }
        }
    }
    
    //-----------------------------------------------------------------------

    public func chatDidFail(withStreamError error: Error?) {
       // Logger.println(object: "chatDidFail")
    }
    
    //-----------------------------------------------------------------------

    public func chatDidConnect() {
      //  Logger.println(object: "chatDidConnect")
    }
    
    //-----------------------------------------------------------------------

    public func chatDidNotConnectWithError(_ error: Error?) {
//        Logger.println(object: "chatDidNotConnectWithError")
    }
    
    //-----------------------------------------------------------------------

    public func chatDidAccidentallyDisconnect() {
       // Logger.println(object: "chatDidAccidentallyDisconnect")
    }
    
    //-----------------------------------------------------------------------

    public func chatDidReconnect() {
       // Logger.println(object: "chatDidReconnect")
    }
    
    //-----------------------------------------------------------------------

    public func chatDidReceiveContactAddRequest(fromUser userID: UInt) {
      //  Logger.println(object: "chatDidReceiveContactAddRequest")
    }
    
    //-----------------------------------------------------------------------

    public func chatContactListDidChange(_ contactList: QBContactList) {
       // Logger.println(object: "chatContactListDidChange")
        
    }
    
    //-----------------------------------------------------------------------

    public func chatDidReceiveContactItemActivity(_ userID: UInt, isOnline: Bool, status: String?) {
       // Logger.println(object: "chatDidReceiveContactItemActivity")
       
    }
    
    //-----------------------------------------------------------------------

    public func chatDidReceiveAcceptContactRequest(fromUser userID: UInt) {
      //  Logger.println(object: "chatDidReceiveAcceptContactRequest")
        
    }
    
    //-----------------------------------------------------------------------

    public func chatDidReceiveRejectContactRequest(fromUser userID: UInt) {
       // Logger.println(object: "chatDidReceiveRejectContactRequest")
        
    }
    
    //-----------------------------------------------------------------------

    public func chatDidReceivePresence(withStatus status: String, fromUser userID: Int) {
      //  Logger.println(object: "chatDidReceivePresence")
        
    }
    
    //-----------------------------------------------------------------------

    public func chatRoomDidReceive(_ message: QBChatMessage, fromDialogID dialogID: String) {
       // Logger.println(object: "chatRoomDidReceive")
     
        
        updateArrayGroupArrayOnNewMessage(message: message,fromDialogID: dialogID) { (groupMessageSelected) in
            if self.delegate != nil, (self.delegate?.responds(to: #selector(QuickbloxManagerDelegate.chatReceive(_:))))! {
                self.delegate?.chatReceive!(message)
            }
        }

    }
    
    //-----------------------------------------------------------------------

    public func chatDidReceivePrivacyListNames(_ listNames: [String]) {
      //  Logger.println(object: "chatDidReceivePrivacyListNames")
        
    }
    
    //-----------------------------------------------------------------------

    public func chatDidReceive(_ privacyList: QBPrivacyList) {
      //  Logger.println(object: "chatDidReceive")
        
    }
    
    //-----------------------------------------------------------------------

    public func chatDidNotReceivePrivacyListNamesDue(toError error: Any?) {
       // Logger.println(object: "chatDidNotReceivePrivacyListNamesDue")
        
    }
    
    //-----------------------------------------------------------------------

    public func chatDidNotReceivePrivacyList(withName name: String, error: Any?) {
       // Logger.println(object: "chatDidNotReceivePrivacyList")
        
    }
    
    //-----------------------------------------------------------------------

    public func chatDidSetPrivacyList(withName name: String) {
      //  Logger.println(object: "chatDidSetPrivacyList")
        
    }
    
    //-----------------------------------------------------------------------

    public func chatDidSetActivePrivacyList(withName name: String) {
      //  Logger.println(object: "chatDidSetActivePrivacyList")
        
    }
    
    //-----------------------------------------------------------------------

    public func chatDidSetDefaultPrivacyList(withName name: String) {
       // Logger.println(object: "chatDidSetDefaultPrivacyList")
        
    }
    
    //-----------------------------------------------------------------------

    public func chatDidNotSetPrivacyList(withName name: String, error: Any?) {
       // Logger.println(object: "chatDidNotSetPrivacyList")
        
    }
    
    //-----------------------------------------------------------------------

    public func chatDidNotSetActivePrivacyList(withName name: String, error: Any?) {
      //  Logger.println(object: "chatDidNotSetActivePrivacyList")
        
    }
    
    //-----------------------------------------------------------------------

    public func chatDidNotSetDefaultPrivacyList(withName name: String, error: Any?) {
       // Logger.println(object: "chatDidNotSetDefaultPrivacyList")
        
    }
    
    //-----------------------------------------------------------------------

    public func chatDidRemovedPrivacyList(withName name: String) {
      //  Logger.println(object: "chatDidRemovedPrivacyList")
        
    }
    
    //-----------------------------------------------------------------------

    public func chatDidDeliverMessage(withID messageID: String, dialogID: String, toUserID userID: UInt) {
       // Logger.println(object: "chatDidDeliverMessage")
    }
    
    //-----------------------------------------------------------------------

    public func chatDidReadMessage(withID messageID: String, dialogID: String, readerID: UInt) {
       // Logger.println(object: "chatDidReadMessage")
    }
    
    //-----------------------------------------------------------------------
}

//-----------------------------------------------------------------------

// MARK: - Extension: QBRTCClientDelegate

//-----------------------------------------------------------------------

extension QuickbloxManager: QBRTCClientDelegate {
    
    //-----------------------------------------------------------------------
    
    func didReceiveNewSession(_ session: QBRTCSession, userInfo: [String : String]? = nil) {
        
//        if sessionForAudioVideoCall != nil {
//            sessionForAudioVideoCall?.rejectCall(nil)
//
//        } else {
//
//            sessionForAudioVideoCall = session
//
//            let chatAudioVideoVC = ChatAudioVideoVC.viewController()
//            chatAudioVideoVC.dictUserInfo = userInfo
//            DispatchQueue.main.async {
//                MenuBaseViewController.sharedInstance().currentViewController().present(chatAudioVideoVC, animated: true, completion: nil)
//            }
//        }
    }
    
    //-----------------------------------------------------------------------
    
    func session(_ session: QBRTCSession, userDidNotRespond userID: NSNumber) {
//        if MenuBaseViewController.sharedInstance().currentViewController() is ChatAudioVideoVC {
//            sessionForAudioVideoCall = nil
//            DispatchQueue.main.async {
//                MenuBaseViewController.sharedInstance().currentViewController().dismiss(animated: true, completion: nil)
//            }
//        }
    }
    
    //-----------------------------------------------------------------------
    
    func session(_ session: QBRTCSession, rejectedByUser userID: NSNumber, userInfo: [String : String]? = nil) {
        
//        if timer != nil {
//            timer?.invalidate()
//            callTimeInterval = 0
//        }
//
//        if MenuBaseViewController.sharedInstance().currentViewController() is ChatAudioVideoVC {
//            sessionForAudioVideoCall = nil
//            DispatchQueue.main.async {
//                MenuBaseViewController.sharedInstance().currentViewController().dismiss(animated: true, completion: nil)
//            }
//        }
    }
    
    //-----------------------------------------------------------------------
    
    func session(_ session: QBRTCSession, acceptedByUser userID: NSNumber, userInfo: [String : String]? = nil) {
        startTimer()
    }
    
    //-----------------------------------------------------------------------
    
    func session(_ session: QBRTCSession, hungUpByUser userID: NSNumber, userInfo: [String : String]? = nil) {
        
    }
    
    //-----------------------------------------------------------------------
    
    func sessionDidClose(_ session: QBRTCSession) {
        
        if timer != nil {
            timer?.invalidate()
            timer = nil
        }
        
        callTimeInterval = 0
        isFromCall = true
        sendCallMessage(session)
        strCallTime = ""
        sessionForAudioVideoCall = nil
    }
    
    //-----------------------------------------------------------------------
}

//-----------------------------------------------------------------------
