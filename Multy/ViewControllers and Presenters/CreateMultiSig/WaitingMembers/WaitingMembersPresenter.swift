//Copyright 2018 Idealnaya rabota LLC
//Licensed under Multy.io license.
//See LICENSE for details

import Foundation
import UIKit

enum BottomButtonStatus: Int {
    case
        hidden =            1,
        inviteCode =        2,
        paymentRequired =   3
}

class WaitingMembersPresenter: NSObject {
    var viewController : WaitingMembersViewController?
    
    var wallet = UserWalletRLM()
    var account : AccountRLM?
    
    var createWalletPrice = 0.001
    
    var bottomButtonStatus = BottomButtonStatus.hidden
    let createdMultiSigWallet = UserWalletRLM()
    
    func viewControllerViewDidLoad() {
//        inviteCode = makeInviteCode()
//        viewController?.openShareInviteVC()
        updateWallet()
    }
    
    func viewControllerViewWillAppear() {
        //        inviteCode = makeInviteCode()
   //     viewController?.openShareInviteVC()
        updateWallet()
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.handleMembersUpdatedNotification(notification:)), name: NSNotification.Name("msMembersUpdated"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.handleWalletDeletedNotification(notification:)), name: NSNotification.Name("msWalletDeleted"), object: nil)
    }
    
    func viewControllerViewWillDisappear() {
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("msMembersUpdated"), object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("msWalletDeleted"), object: nil)
    }

    func kickOwnerWithIndex(index: Int) {
        let owner = wallet.multisigWallet!.owners[index]
        DataManager.shared.kickFromMultisigWith(wallet: wallet, addressToKick: owner.address) { [unowned self] result in
            switch result {
            case .success(_):
                self.updateWallet()
            case .failure(let error):
                self.viewController?.presentAlert(with: error)
            }
        }
    }
    
    func viewControllerViewDidLayoutSubviews() {
        
    }
    
    @objc fileprivate func handleWalletDeletedNotification(notification : Notification) {
        let inviteCode = notification.userInfo!["inviteCode"] as! String
        if inviteCode == wallet.multisigWallet?.inviteCode {
            DispatchQueue.main.async {
                if !(self.wallet.multisigWallet?.amICreator)! {
                    self.viewController?.navigationController?.popToRootViewController(animated: true)
                }
            }
        }
    }
    
    @objc fileprivate func handleMembersUpdatedNotification(notification : Notification) {
        let inviteCode = notification.userInfo!["inviteCode"] as! String
        if inviteCode == wallet.multisigWallet?.inviteCode {
            if notification.userInfo!["kickedAddress"] != nil && wallet.multisigWallet?.linkedWalletAddress == notification.userInfo!["kickedAddress"] as! String {
                self.viewController?.navigationController?.popToRootViewController(animated: true)
                return
            }
            
            DispatchQueue.main.async {
                self.updateWallet()
            }
        }
    }
        
    fileprivate func updateWallet() {
        DataManager.shared.getOneMultisigWalletVerbose(inviteCode: wallet.multisigWallet!.inviteCode, blockchain: wallet.blockchainType) { [unowned self] (wallet, error) in
            DispatchQueue.main.async {
                if wallet != nil {
                    self.wallet = wallet!
                    self.viewController?.updateUI()
                }
            }
        }
    }
    
    func payForMultiSig() {
        DataManager.shared.getWallet(primaryKey: wallet.multisigWallet!.linkedWalletID) { [unowned self] in
            switch $0 {
            case .success(let wallet):
                self.createAndSendMSTransaction(linkedWallet: wallet)
                break;
            case .failure(let errorString):
                print(errorString)
                break;
            }
        }
    }
    
    func createAndSendMSTransaction(linkedWallet: UserWalletRLM) {
        var binData = account!.binaryDataString.createBinaryData()!
        let ownersString = createOwnersString()
        let result = DataManager.shared.createMultiSigWallet(binaryData: &binData,
                                                             wallet: linkedWallet,
                                                             creationPriceString: "0",// "100000000000000000",//0.1 ETH
                                                             gasPriceString: "1000000000",
                                                             gasLimitString: "5000000",
                                                             owners: ownersString,
                                                             confirmationsCount: UInt32(wallet.multisigWallet!.signaturesRequiredCount))
        
        if result.isTransactionCorrect {
            let newAddressParams = [
                "walletindex"   : linkedWallet.walletID.intValue,
                "address"       : "",
                "addressindex"  : linkedWallet.addresses.count,
                "transaction"   : result.message,
                "ishd"          : NSNumber(booleanLiteral: false)
                ] as [String : Any]
            
            let params = [
                "currencyid": linkedWallet.chain,
                "networkid" : linkedWallet.chainType,
                "payload"   : newAddressParams
                ] as [String : Any]
            
            guard viewController!.presentNoInternetScreen() else {
                
                return
            }
            
            DataManager.shared.sendHDTransaction(transactionParameters: params) { [unowned self] (dict, error) in
                print("---------\(dict)")
                
                if let code = dict?["code"] as? Int, code == 200 {
                    self.viewController?.openNewlyCreatedWallet()
                } else {
                    if error != nil {
                        self.viewController?.presentAlert(with: error?.localizedDescription)
                    } else {
                        self.viewController?.presentAlert(with: self.viewController?.localize(string: Constants.somethingWentWrongString))
                    }
                }
            }
        } else {
            
        }
    }
    
    func createOwnersString() -> String {
        let ownersString = wallet.multisigWallet!.owners.map { $0.address }.joined(separator: ", ")
        
        return "[\(ownersString)]"
    }
}