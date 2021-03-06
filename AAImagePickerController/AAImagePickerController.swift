//
//  AAImagePickerController.swift
//  AAImagePickerControllerDemo
//
//  Created by Anas perso on 16/05/15.
//  Copyright (c) 2015 Anas. All rights reserved.
//

import UIKit
import AssetsLibrary

// MARK: - Constants
let AAImageCellIdentifier = "AAImageCellIdentifier"
let AATakePhotoCellIdentifier = "AATakePhotoCellIdentifier"

// MARK: - AAImagePickerControllerDelegate
protocol AAImagePickerControllerDelegate : NSObjectProtocol {
  func imagePickerControllerDidFinishSelection(images: [ImageItem])
  func imagePickerControllerDidCancel()
}

// MARK: - Models
class ImageGroup {
  var name: String!
  var group: ALAssetsGroup!
}

class ImageItem : NSObject {
  private var originalAsset: ALAsset?
  var thumbnailImage: UIImage?
  lazy var image: UIImage? = {
    if let origAsset = self.originalAsset {
      return self.fullScreenImage
    } else {
      return self.image
    }
    }()
  lazy var fullScreenImage: UIImage? = {
    return UIImage(CGImage: self.originalAsset?.defaultRepresentation().fullScreenImage().takeUnretainedValue())
    }()
  lazy var fullResolutionImage: UIImage? = {
    return UIImage(CGImage: self.originalAsset?.defaultRepresentation().fullResolutionImage().takeUnretainedValue())
    }()
  var url: NSURL?
  
  override func isEqual(object: AnyObject?) -> Bool {
    let other = object as! ImageItem
    if let url = self.url, otherUrl = other.url {
      return url.isEqual(otherUrl)
    }
    return false
  }
}

// MARK: - AAImagePickerController
class AAImagePickerController : UINavigationController {

  internal weak var pickerDelegate : AAImagePickerControllerDelegate?
  var listController : AAImagePickerControllerList!
  var allowsMultipleSelection : Bool = true
  var maximumNumberOfSelection : Int = 0
  var numberOfColumnInPortrait : Int = 4
  var numberOfColumnInLandscape : Int = 7
  var showTakePhoto : Bool = true
  var selectionColor = UIColor.clearColor() {
    didSet {
      self.listController.selectionColor = selectionColor
    }
  }
  internal var selectedItems = [ImageItem]() {
    willSet(newValue) {
      let currentCount = selectedItems.count
      println("selectedItems = \(currentCount)")
      if newValue.count == 0 {
        addBtn.title = "Add"
        addBtn.enabled = false
      } else if (newValue.count != currentCount) {
        addBtn.title = "Add (\(newValue.count))"
        addBtn.enabled = true
      }
    }
  }
  lazy internal var addBtn : UIBarButtonItem = {
    let btn : UIBarButtonItem = UIBarButtonItem(title: "Add", style: .Done, target: self, action: "addAction")
    btn.enabled = false
    return btn
  }()
  
  // MARK: Initialization
  convenience init() {
    let aListController = AAImagePickerControllerList()
    self.init(rootViewController: aListController)
    listController = aListController
  }
  
  // MARK: View lifecycle
  override func viewDidLoad() {
    super.viewDidLoad()
  }
  
  // MARK: UINavigationController
  override func pushViewController(viewController: UIViewController, animated: Bool) {
    super.pushViewController(viewController, animated: animated)
    
    self.topViewController.navigationItem.rightBarButtonItem = addBtn

    if self.viewControllers.count == 1 &&
      self.topViewController?.navigationItem.leftBarButtonItem == nil {
      self.topViewController.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: UIBarButtonSystemItem.Cancel, target: self, action: "cancelAction")
    }
  }
  
  // MARK: Delegate
  func cancelAction() {
    if let aDelegate = self.pickerDelegate {
      aDelegate.imagePickerControllerDidCancel()
    }
  }
 
  func addAction() {
    if let delegate = self.pickerDelegate {
      delegate.imagePickerControllerDidFinishSelection(selectedItems)
    }
  }
}

internal extension UIViewController {
  var imagePickerController: AAImagePickerController? {
    get {
      let nav = self.navigationController
      if nav is AAImagePickerController {
        return nav as? AAImagePickerController
      } else {
        return nil
      }
    }
  }
}

// MARK : AACollectionViewFlowLayout
internal class AACollectionViewFlowLayout : UICollectionViewFlowLayout {
  static let interval: CGFloat = 1
  
  func commonInit() {
    self.minimumInteritemSpacing = AACollectionViewFlowLayout.interval
    self.minimumLineSpacing = AACollectionViewFlowLayout.interval
  }
  
  override init() {
    super.init()
    self.commonInit()
  }

  required init(coder aDecoder: NSCoder) {
    super.init(coder: aDecoder)
    self.commonInit()
  }
}

// MARK: - AAImagePickerControllerList
class AAImagePickerControllerList : UICollectionViewController {

  lazy private var albumPickerView = AKPickerView()
  lazy private var library: ALAssetsLibrary = {
    return ALAssetsLibrary()
    }()
  lazy private var groups: NSMutableArray = {
    return NSMutableArray()
    }()
  private lazy var imageItems: NSMutableArray = {
    return NSMutableArray()
    }()
  var selectionColor = UIColor(red: 55/255, green: 93/255, blue: 129/255, alpha: 1.0)
  var currentGroupSelection : Int?
  var accessDeniedView: UIView = {
    let label = UILabel()
    label.text = "This application doesn't have access to your photos"
    label.textAlignment = NSTextAlignment.Center
    label.textColor = UIColor.lightGrayColor()
    label.numberOfLines = 0
    return label
    }()
  
  // MARK: Initialization
  override init(collectionViewLayout layout: UICollectionViewLayout) {
    super.init(collectionViewLayout: layout)
  }
  
  convenience init() {
    let layout = AACollectionViewFlowLayout()
    self.init(collectionViewLayout: layout)
  }
  
  required init(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  // MARK: View lifecycle
  override func viewDidLoad() {
    super.viewDidLoad()
    
    albumPickerInitialisation()
    
    collectionView!.backgroundColor = UIColor.whiteColor()
    collectionView!.allowsMultipleSelection = imagePickerController!.allowsMultipleSelection
    collectionView!.registerClass(AAImagePickerCollectionCell.self, forCellWithReuseIdentifier: AAImageCellIdentifier)
    collectionView!.registerClass(AATakePhotoCollectionCell.self, forCellWithReuseIdentifier: AATakePhotoCellIdentifier)
  }
  
  override func viewDidAppear(animated: Bool) {
    super.viewDidAppear(animated)
    
    updateGroups { () -> () in
      self.updateImagesList()
    }
  }
  
  // MARK: Library methods
  func updateGroups(callback: () -> ()) {
    library.enumerateGroupsWithTypes(ALAssetsGroupAll, usingBlock: { (group: ALAssetsGroup!, stop: UnsafeMutablePointer<ObjCBool>) -> Void in
      if group != nil {
        if group.numberOfAssets() != 0 {
          let groupName = group.valueForProperty(ALAssetsGroupPropertyName) as! String
          let assetGroup = ImageGroup()
          assetGroup.name = groupName
          assetGroup.group = group
          self.groups.insertObject(assetGroup, atIndex: 0)
        }
      } else {
        self.albumPickerView.reloadData()
        callback()
      }
      }, failureBlock: { (error: NSError!) -> Void in
        self.accessDeniedView.frame = self.collectionView!.bounds
        self.collectionView!.addSubview(self.accessDeniedView)
    })
  }
  
  func updateImagesList() {
    let selectedAlbum = self.albumPickerView.selectedItem
    let currentGroup = groups[selectedAlbum] as! ImageGroup

    self.imageItems.removeAllObjects()
    currentGroup.group.setAssetsFilter(ALAssetsFilter.allPhotos())
    currentGroup.group.enumerateAssetsUsingBlock { (result: ALAsset!, index: Int, stop: UnsafeMutablePointer<ObjCBool>) -> Void in
      if result != nil {
        let item = ImageItem()
        item.thumbnailImage = UIImage(CGImage:result.thumbnail()?.takeUnretainedValue())
        item.url = result.valueForProperty(ALAssetPropertyAssetURL) as? NSURL
        item.originalAsset = result
        self.imageItems.insertObject(item, atIndex: 0)
      } else {
        self.collectionView!.reloadData()
      }
    }
  }
  
  // MARK: UICollectionViewDataSource
  override func numberOfSectionsInCollectionView(collectionView: UICollectionView) -> Int {
    return 1
  }
  
  override func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
    if imageItems.count > 0 {
      return imageItems.count + (imagePickerController?.showTakePhoto == true ? 1 : 0)
    }
    return 0
  }
  
  override func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
    if indexPath.row == 0 && imagePickerController?.showTakePhoto == true {
      let takePhotoCell = collectionView.dequeueReusableCellWithReuseIdentifier(AATakePhotoCellIdentifier, forIndexPath: indexPath) as! AATakePhotoCollectionCell
      animateCell(takePhotoCell, pos: indexPath.row)
      return takePhotoCell
    } else {
      let item = imageItems[indexPath.row - (imagePickerController?.showTakePhoto == true ? 1 : 0)] as! ImageItem
      let cell = collectionView.dequeueReusableCellWithReuseIdentifier(AAImageCellIdentifier, forIndexPath: indexPath) as! AAImagePickerCollectionCell
      cell.thumbnail = item.thumbnailImage
      cell.selectionColor = selectionColor
      if find(imagePickerController!.selectedItems, item) != nil {
        cell.selected = true
        collectionView.selectItemAtIndexPath(indexPath, animated: false, scrollPosition: .None)
      } else {
        cell.selected = false
        collectionView.deselectItemAtIndexPath(indexPath, animated: false)
      }
      animateCell(cell, pos: indexPath.row)
      return cell
    }
  }
  
  func animateCell(cell: UICollectionViewCell, pos: Int) {
    cell.transform = CGAffineTransformMakeScale(0, 0)
    UIView.animateWithDuration(0.3, delay:  Double(pos) * 0.01, options: UIViewAnimationOptions.CurveEaseInOut,
      animations: { () -> Void in
        cell.transform = CGAffineTransformMakeScale(1, 1)
    }, completion: nil)
  }
  
  // MARK: UICollectionViewDelegate
  override func collectionView(collectionView: UICollectionView, shouldSelectItemAtIndexPath indexPath: NSIndexPath) -> Bool {
    let max = imagePickerController!.maximumNumberOfSelection
    return max > 0 ? (imagePickerController!.selectedItems.count < max) : true
  }
  
  override func collectionView(collectionView: UICollectionView, didSelectItemAtIndexPath indexPath: NSIndexPath) {
    if indexPath.row == 0 && imagePickerController?.showTakePhoto == true {
      collectionView.deselectItemAtIndexPath(indexPath, animated: false)
      if UIImagePickerController.isSourceTypeAvailable(.Camera) {
        var picker = UIImagePickerController()
        picker.delegate = self
        picker.allowsEditing = true
        picker.sourceType = UIImagePickerControllerSourceType.Camera
        self.presentViewController(picker, animated: true, completion: nil)
      } else {
        let alert = UIAlertView(title: "Error", message: "This device has no camera", delegate: nil, cancelButtonTitle: "Ok")
        alert.show()
      }
    } else {
      let item = imageItems[indexPath.row - (imagePickerController?.showTakePhoto == true ? 1 : 0)] as! ImageItem
      if find(imagePickerController!.selectedItems, item) == nil {
        imagePickerController!.selectedItems.append(item)
      }
    }
  }
  
  override func collectionView(collectionView: UICollectionView, didDeselectItemAtIndexPath indexPath: NSIndexPath) {
    if indexPath.row != 0 {
      let item = imageItems[indexPath.row - (imagePickerController?.showTakePhoto == true ? 1 : 0)] as! ImageItem
      imagePickerController!.selectedItems.removeAtIndex(find(imagePickerController!.selectedItems, item)!)
    }
  }
  
  // MARK : Rotation
  override func willRotateToInterfaceOrientation(toInterfaceOrientation: UIInterfaceOrientation, duration: NSTimeInterval) {
    super.willRotateToInterfaceOrientation(toInterfaceOrientation, duration: duration)
    self.collectionView!.collectionViewLayout.invalidateLayout()
  }
}

extension AAImagePickerControllerList  : UICollectionViewDelegateFlowLayout {
  func collectionView(collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAtIndexPath indexPath: NSIndexPath) -> CGSize {
    let numberOfColumns : Int
    let side : CGFloat
    if UIInterfaceOrientationIsPortrait(UIApplication.sharedApplication().statusBarOrientation) {
      numberOfColumns = imagePickerController!.numberOfColumnInPortrait
    } else {
      numberOfColumns = imagePickerController!.numberOfColumnInLandscape
    }
    side = (CGRectGetWidth(collectionView.frame) - AACollectionViewFlowLayout.interval * CGFloat(numberOfColumns - 1)) / CGFloat(numberOfColumns)
    return CGSizeMake(side, side)
  }
}

extension AAImagePickerControllerList : UIImagePickerControllerDelegate, UINavigationControllerDelegate {
  func imagePickerController(picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [NSObject : AnyObject]) {
    let item = ImageItem()
    item.image = info[UIImagePickerControllerEditedImage] as? UIImage
    item.url = info[UIImagePickerControllerReferenceURL] as? NSURL
    imagePickerController!.selectedItems = [item]
    imagePickerController!.addAction()
    picker.dismissViewControllerAnimated(true, completion:nil)
  }
  
  func imagePickerControllerDidCancel(picker: UIImagePickerController) {
    picker.dismissViewControllerAnimated(true, completion: nil)
  }
}

extension AAImagePickerControllerList : AKPickerViewDelegate, AKPickerViewDataSource {
  
  func albumPickerInitialisation() {
    self.albumPickerView.delegate = self
    self.albumPickerView.dataSource = self
    self.albumPickerView.font = UIFont(name: "HelveticaNeue-Light", size: 20)!
    self.albumPickerView.highlightedFont = UIFont(name: "HelveticaNeue", size: 20)!
    self.albumPickerView.interitemSpacing = 10.0
    self.albumPickerView.viewDepth = 1000.0
    self.albumPickerView.pickerViewStyle = .Wheel
    self.albumPickerView.maskDisabled = false
    self.albumPickerView.autoresizingMask =  UIViewAutoresizing.FlexibleWidth | UIViewAutoresizing.FlexibleHeight
    if self.navigationController != nil {
      self.albumPickerView.frame = self.navigationController!.navigationBar.bounds
    }
    self.navigationItem.titleView = self.albumPickerView
  }
  
  func numberOfItemsInPickerView(pickerView: AKPickerView) -> Int {
    return groups.count
  }
  
  func pickerView(pickerView: AKPickerView, titleForItem item: Int) -> String {
    let assetGroup : ImageGroup = groups[item] as! ImageGroup
    return assetGroup.name
  }
  
  func pickerView(pickerView: AKPickerView, didSelectItem item: Int) {
    if currentGroupSelection == nil || currentGroupSelection != item {
      currentGroupSelection = item
      updateImagesList()
    }
  }
}

// MARK: - UIImage extension
extension UIImage {
  func imageWithColor(color: UIColor) -> UIImage {
    let rect = CGRectMake(0, 0, self.size.width, self.size.height)
    UIGraphicsBeginImageContext(rect.size)
    let context = UIGraphicsGetCurrentContext()
    color.set()
    CGContextTranslateCTM(context, 0, self.size.height)
    CGContextScaleCTM(context, 1.0, -1.0)
    CGContextClipToMask(context, rect, self.CGImage)
    CGContextFillRect(context, rect)
    let image = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return image
  }
}

// MARK: - AAImagePickerCollectionCell
class AAImagePickerCollectionCell: UICollectionViewCell {
  private var imageView = UIImageView()
  private var selectedView = UIImageView(image: UIImage(named: "check"))
  private var overlay = UIView()
  
  var selectionColor = UIColor.clearColor() {
    didSet {
      layer.borderColor = selectionColor.CGColor
//      selectedView.image = selectedView.image?.imageWithColor(selectionColor)
    }
  }
  
  var thumbnail: UIImage! {
    didSet {
      self.imageView.image = thumbnail
    }
  }
  
  override var selected: Bool {
    didSet {
      selectedView.hidden = !super.selected
      overlay.hidden = !super.selected
      layer.borderWidth = super.selected ? 0.6 : 0
    }
  }
  
  override init(frame: CGRect) {
    super.init(frame: frame)
    
    imageView.frame = self.bounds
    overlay.frame = self.bounds
    overlay.backgroundColor = UIColor.whiteColor().colorWithAlphaComponent(0.2)
    self.contentView.addSubview(imageView)
    self.contentView.addSubview(overlay)
    self.contentView.addSubview(selectedView)
  }
  
  required init(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  override func layoutSubviews() {
    super.layoutSubviews()
    
    imageView.frame = self.bounds
    overlay.frame = self.bounds
    selectedView.frame.size = CGSizeMake(self.contentView.bounds.width / 4, self.contentView.bounds.height / 4)
    selectedView.frame.origin = CGPoint(x: self.contentView.bounds.width - selectedView.bounds.width - 5,
      y: self.contentView.bounds.height - selectedView.bounds.height - 5)
  }
}

// MARK: - AATakePhotoCollectionCell
class AATakePhotoCollectionCell: UICollectionViewCell {
  private var imageView = UIImageView(image: UIImage(named: "take_photo"))
  
  override init(frame: CGRect) {
    super.init(frame: frame)
    
    imageView.frame = self.bounds
    self.contentView.addSubview(imageView)
  }
  
  required init(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  override func layoutSubviews() {
    super.layoutSubviews()
    
    imageView.frame = self.bounds
  }
}

