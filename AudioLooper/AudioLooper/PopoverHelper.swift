import UIKit

extension UIViewController {
    func configurePopoverForIPad(_ popoverController: UIPopoverPresentationController?) {
        guard let popover = popoverController else { return }
        
        popover.sourceView = self.view
        popover.sourceRect = CGRect(
            x: self.view.bounds.midX,
            y: self.view.bounds.midY,
            width: 0,
            height: 0
        )
        popover.permittedArrowDirections = []
    }
}

class PopoverHelper {
    static func configurePopover(_ popoverController: UIPopoverPresentationController?) {
        guard let popover = popoverController else { return }
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootView = window.rootViewController?.view {
            
            popover.sourceView = rootView
            popover.sourceRect = CGRect(
                x: rootView.bounds.midX,
                y: rootView.bounds.midY,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }
    }
}