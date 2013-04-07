//
//  NSManagedObject+PropertiesDictionary.h
//
//  Created by David Pratt on 2/17/13.
//
//

#import <CoreData/CoreData.h>

@interface NSManagedObject (PropertiesDictionary)

//Set the attributes and relationships of this object based on the keys provided in the dictionary. If a key is present
//in the dictionary and the key matches a property name on this entity, it's value is updated with the value in the
//dictionary. If the value in the dictionary is NSNull, the value is set to nil. If the key is not present in the
//dictionary, the property on this object is left unchanged.
//
//In general, it's assumed that this object 'owns' and is responsbile for the lifecycle of a child object if the
//relationship defintion (be it 1 to 1 or 1 to many) has a deletion policy of NSCascadeDeleteRule. This means that if
//the target entity in a relationship on this object would be replaced or removed by the values in the supplied NSDictionary,
//it is deleted. If the deletion policy is not NSCascadeDeleteRule, the object is just un-related. This behavior may
//or may not cause object leaks in your graph. If this is the case, you need to add an explicit implementation of
//willSave to your NSManagedObject sublass for the destination entity that checks if it has already deleted and
//if it has any other objects pointing to it. If it does not, it should delete itself. See the related class
//CSGarbageCollectedManagedObject for an example of how to do this.
//
//This method also knows how to do updates to an existing 1 to many collection. If the destination entity's companion Objective-C
//class object responds to the selector 'objectIdentifierPropertyName', the resulting NSString is used as the name of a property
//in the managed object that uniquely identifies it in a collection. For example, if you have a 1 to many collection of
//Manager -> Employees, the Employee class may respond to 'objectIdentifierPropertyName' by returning the string 'employeeId'.
//This property is then accessed on all of the children in the collection and the corresponding values from the input NSDictionary
//are used to correlate objects in the NSDictionary to existing values. If there is a match, the existing object is used.
//If an object with a given ID exists in the NSDictionary but not in the current value of the relationship, a new object
//is created. Inversely, if an object does *not* appear in the NSDictionary but is in the existing collection, it is
//removed from the relationship and optionally deleted (if the deletion policy on the parent's relationship definition is set
//to 'Cascade').
//NOTE - it is assumed that the value associated with the designated object ID property actually will be unique
//in the collection. If it is not, undefined behavior can (and will) occur.
- (BOOL)setValuesAndRelationshipsForKeysWithDictionary:(NSDictionary *)keyedValues;

@end
