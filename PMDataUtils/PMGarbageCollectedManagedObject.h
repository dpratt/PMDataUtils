//
//  NSGarbageCollectedManagedObject.h
//
//  Created by David Pratt on 2/21/13.
//
//

#import <CoreData/CoreData.h>

//This is a class that will run garbage collection on itself when it is saved.
//An object is deemed to be garbage when it has no outgoing pointers to objects it does not 'own'. Object ownership
//is defined simply as a relation with a delete policy set to NSCascadeDeleteRule - any other deletion policy
//indicates that this object is not responsible for the lifecycle of the child object. The assumption made here is that
//an outgoing weak pointer to an object means that the object on the other side of the relation is strongly retaining this object, and thus
//this object is not garbage.
//
//The edge case of an object with no external 'weak' relations is handled here as well, with the simple rule
//that such an entity cannot ever be automatically determined to be garbage, and thus will
//never automatically delete itself.
//
//NOTE - IT IS IMPORTANT THAT ALL YOUR RELATIONSHIPS ARE BIDIRECTIONAL. If you have unidirectional relationships
//garbage collection will fail and you will leak objects in the core data store.
//
//A common usecase for this class is to designate an entity as the 'root' entity in the tree of your data model. This 'root'
//entity does NOT utilize this class, but rather just inherits from NSManagedObject. All of the other dependent entities
//in your model will subclass NSGarbageCollectedManagedObject and thus gain this behavior.
//
//This class is commonly (but not exclusively) used to ensure that many-to-many collections do not leak objects
//when members of the relationship collection are un-related. Take the example of a root entity 'DVD' and a child entity 'Tag'
//with a many-to-many relationship defined between them. A given tag may be assigned to multiple DVDs. If a subsequently
//removed from all of the DVDs, it will automatically delete itself.
@interface PMGarbageCollectedManagedObject : NSManagedObject

@end
