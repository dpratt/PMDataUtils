//
//  NSManagedObject+PropertiesDictionary.m
//
//  Created by David Pratt on 2/17/13.
//
//

#import "NSManagedObject+PropertiesDictionary.h"
#import "ISO8601DateFormatter.h"

#import "PMDataUtils.h"

@implementation NSManagedObject (PropertiesDictionary)

- (BOOL)setValuesAndRelationshipsForKeysWithDictionary:(NSDictionary *)keyedValues error:(NSError **)error {
    
    NSSet *inputKeys = [NSSet setWithArray:keyedValues.allKeys];
    
    @try {
        //set all the attributes on the managed object
        NSDictionary *attributes = [[self entity] attributesByName];
        //interate through the attribute names, not the names in the dictionary
        
        for (NSString *attribute in attributes) {
            //If the attribute name is not present in the input, don't change the value
            if (![inputKeys containsObject:attribute]) {
                continue;
            }
            
            id value = [keyedValues objectForKey:attribute];
            if ([NSNull null] == value) {
                value = nil;
            }
            //TODO: This type coercion is not exhaustive - we should add cases for all of the
            //potential inputs from a JSON based NSDictionary and convert them properly
            //the below code handles 95% of cases.
            NSAttributeType attributeType = [[attributes objectForKey:attribute] attributeType];
            if ((attributeType == NSStringAttributeType) && ([value isKindOfClass:[NSNumber class]])) {
                value = [value stringValue];
            } else if ([value isKindOfClass:[NSString class]]) {
                switch(attributeType) {
                    case NSDateAttributeType: {
                        ISO8601DateFormatter *formatter = [[ISO8601DateFormatter alloc] init];
                        value = [formatter dateFromString:value];
                    }
                        break;
                    case NSInteger16AttributeType:
                    case NSInteger32AttributeType:
                    case NSInteger64AttributeType:
                        value = [NSNumber numberWithInteger:[value integerValue]];
                        break;
                    case NSDecimalAttributeType:
                        value = [NSDecimalNumber decimalNumberWithString:value];
                    case NSDoubleAttributeType:
                        value = [NSNumber numberWithDouble:[value doubleValue]];
                    case NSFloatAttributeType:
                        value = [NSNumber numberWithFloat:[value floatValue]];
                    case NSBooleanAttributeType:
                        value = [NSNumber numberWithInteger:[value boolValue]];
                    default:
                        break;
                }
            }
            //TODO: deal with NSTransformableAttributeType
            [self setValue:value forKey:attribute];
        }
        
        //okay, now set the relationships
        NSDictionary *relationships = [[self entity] relationshipsByName];
        for (NSString *relationshipName in relationships) {
            if (![inputKeys containsObject:relationshipName]) {
                //skip the attribute if it's not present in the input
                continue;
            }
            
            NSRelationshipDescription *relationship = [relationships valueForKey:relationshipName];
            id value = [keyedValues objectForKey:relationshipName];
                        
            //See if we can uniquely identify managed objects of the destination entity type inside of the context
            //This allows us to re-use objects in the context (where appropriate)
            NSString *destinationEntityUniqueIdPropertyName = nil;
            Class childClass = NSClassFromString(relationship.destinationEntity.managedObjectClassName);
            if([childClass respondsToSelector:@selector(uniqueIdentifierPropertyName)]) {
                destinationEntityUniqueIdPropertyName = [childClass performSelector:@selector(uniqueIdentifierPropertyName)];
                //ensure that the collectionIdName is an existing scalar attribute on the entity
                if ([[relationship.destinationEntity attributesByName] objectForKey:destinationEntityUniqueIdPropertyName] == nil) {
                    NSLog(@"Unique ID parameter set to %@ on entity %@, but is not an attribute.", destinationEntityUniqueIdPropertyName, [self.entity name]);
                    destinationEntityUniqueIdPropertyName = nil;
                }
            }
            
            
            if (!relationship.isToMany) {

                //this is a 1-to-1 relationship
                if (value == nil || value == [NSNull null]) {
                    if ( !relationship.isOptional ) {
                        *error = [NSError errorWithDomain:kPMDataUtilsErrorDomain
                                                     code:kPMDataUtilsGeneral
                                                 userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"ERROR - expected value for required relationship %@ in object %@, got nil.", relationshipName, [self.entity name]]}];
                        return NO;
                    }

                    //null out the value - but ONLY if it's owned by this object
                    //if it's not a cascade delete, it's assumed that this is the
                    //child side of a bidirectional relationship
                    if(relationship.deleteRule == NSCascadeDeleteRule) {
                        //since it's a cascade delete, we can assume that this object 'owns' the child so delete it
                        NSManagedObject *oldValue = [self valueForKey:relationshipName];
                        [oldValue.managedObjectContext deleteObject:oldValue];
                    }
                    //now un-relate the object
                    [self setValue:nil forKey:relationshipName];
                } else {
                    //a 1-to-1 relationship must be described by an NSDictionary element in the input
                    //since the other side of the relation must be another NSManagedObject
                    if (![value isKindOfClass:[NSDictionary class]]) {
                        NSLog(@"Expecting NSDictionary value for relationship named %@ in object %@, but got %@ instead.",
                              relationshipName, [self.entity name], NSStringFromClass([value class]));
                        return NO;
                    }
                    NSDictionary *childDict = (NSDictionary *)value;
                    //get the current value (if any)
                    NSManagedObject *child = [self valueForKey:relationshipName];
                    if(child == nil) {
                        //we do not have an existing value
                        
                        //if the inverse relationship is a toMany it means that
                        //this object has the ability to use an already existing object somewhere from the moc
                        //attempt to look up an object somewhere in the moc that matches what we're looking for
                        //we can only do this, though, if the child entity class defines a property name that is a 'primary key'
                        if(relationship.inverseRelationship.isToMany && destinationEntityUniqueIdPropertyName != nil) {
                            
                            //the 'primary key' of the child object
                            id childIdentifierValue = [childDict objectForKey:destinationEntityUniqueIdPropertyName];
                            if(childIdentifierValue != nil) {
                                NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
                                fetch.entity = relationship.destinationEntity;
                                fetch.predicate = [NSPredicate predicateWithFormat:@"%K == %@", destinationEntityUniqueIdPropertyName, childIdentifierValue];
                                NSError *fetchError = nil;
                                NSArray *results = [self.managedObjectContext executeFetchRequest:fetch error:&fetchError];
                                if(fetchError != nil) {
                                    *error = fetchError;
                                    return NO;
                                }
                                //                                if(results.count > 1) {
                                //                                    NSLog(@"Found %i candidates for relationship %@ on entity %@ for identifier value %@. Using random object.",
                                //                                          results.count, relationshipName, relationship.destinationEntity.name, childIdentifierValue);
                                //                                }
                                child = [results lastObject];
                            } else {
                                NSLog(@"The property %@ returned a nil value from the input NSDictionary. Cannot look up an existing object.", destinationEntityUniqueIdPropertyName);
                            }
                        }
                        if(child == nil) {
                            //need to create a new value
                            child = [[NSManagedObject alloc] initWithEntity:relationship.destinationEntity insertIntoManagedObjectContext:self.managedObjectContext];
                            if(child == nil) {
                                NSString *errorMessage = [NSString stringWithFormat:@"Could not allocate object of type %@", relationship.destinationEntity.name];
                                *error = [NSError errorWithDomain:kPMDataUtilsErrorDomain
                                                             code:kPMDataUtilsGeneral
                                                         userInfo:@{NSLocalizedDescriptionKey : errorMessage}];
                                return NO;
                            }
                        }
                    }
                    if(![child setValuesAndRelationshipsForKeysWithDictionary:childDict error:error]) {
                        return NO;
                    }
                    [self setValue:child forKey:relationshipName];
                }
            } else {
                //handle a 1-to-many relationship
                if (value == nil || value == [NSNull null]) {
                    
                    if ( !relationship.isOptional ) {
                        *error = [NSError errorWithDomain:kPMDataUtilsErrorDomain
                                                     code:kPMDataUtilsGeneral
                                                 userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"ERROR - expected value for required relationship %@ in object %@, got nil.", relationshipName, [self.entity name]]}];
                        return NO;
                    }
                    
                    NSMutableSet *existingChildren = [self mutableSetValueForKey:relationshipName];
                    if(relationship.deleteRule == NSCascadeDeleteRule) {
                        //since it's a cascade delete, we can assume that this object 'owns' it's children so delete them
                        for (NSManagedObject *child in existingChildren) {
                            [child.managedObjectContext deleteObject:child];
                        }
                    }
                    //remove them from the relationship
                    [existingChildren removeAllObjects];
                } else {
                    //this is a 1-to-many relationship
                    //a 1-to-many relationship must be described by an NSArray element in the input
                    if (![value isKindOfClass:[NSArray class]]) {
                        NSString *errorMessage = [NSString stringWithFormat:@"Expecting NSArray value for relationship named %@ in object %@, but got %@ instead.",
                                                  relationshipName, [self.entity name], NSStringFromClass([value class])];
                        *error = [NSError errorWithDomain:kPMDataUtilsErrorDomain
                                                     code:kPMDataUtilsGeneral
                                                 userInfo:@{NSLocalizedDescriptionKey : errorMessage}];
                        return NO;
                    }
                    NSArray *inputValues = (NSArray *)value;
                    
                    if ( !relationship.isOptional && inputValues.count == 0) {
                        *error = [NSError errorWithDomain:kPMDataUtilsErrorDomain
                                                     code:kPMDataUtilsGeneral
                                                 userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"ERROR - expected value for required relationship %@ in object %@, got nil.", relationshipName, [self.entity name]]}];
                        return NO;
                    }

                    
                    //we expect all of the child values to be NSDictionaries
                    for(id inputChild in inputValues) {
                        if (![inputChild isKindOfClass:[NSDictionary class]]) {
                            NSString *errorMessage = [NSString stringWithFormat:@"Expecting NSDictionary child for relationship %@ in object %@, but got %@ instead.",
                                                      relationshipName, [self.entity name], NSStringFromClass([inputChild class])];
                            *error = [NSError errorWithDomain:kPMDataUtilsErrorDomain
                                                         code:kPMDataUtilsGeneral
                                                     userInfo:@{NSLocalizedDescriptionKey : errorMessage}];
                            return NO;
                        }
                    }
                    
                    BOOL isManyToMany = relationship.isToMany && relationship.inverseRelationship.isToMany;
                    
                    if(destinationEntityUniqueIdPropertyName != nil) {
                        
                        //create the lookup maps and sets of keys
                        //check to see if there is more than one value with the defined ID key
                        NSArray *allInputIds = [inputValues valueForKey:destinationEntityUniqueIdPropertyName];
                        NSCountedSet *uniqueInputKeys = [NSCountedSet setWithArray:allInputIds];
                        if(uniqueInputKeys.count != allInputIds.count) {
                            //this means that there is more than one object in the input
                            //with a given value for the ID property - this is bad, since it
                            //violates our invariant that the ID property must be unique and
                            //a way to identify a given object in the collection.
                            NSSet *duplicateIds = [uniqueInputKeys objectsPassingTest:^BOOL(id obj, BOOL *stop) {
                                return [uniqueInputKeys countForObject:obj] > 1;
                            }];
                            NSLog(@"WARNING! The JSON input used to set the values in relationship %@ on entity %@ contains mutiple values for the supposedly unique key %@. This will cause undefined behavior on the target NSManagedObject. (The likeliest result is that one of the inputs is completely ignored.) Keys with non-unique occurences - %@", relationshipName, self.entity.name, destinationEntityUniqueIdPropertyName, duplicateIds);
                        }
                        
                        //have to get orderedExisting because the existing is an NSSet
                        //basically, just turn the set into an array so that we can then
                        //transform it into a dictionary with the key being the value of the ID property
                        //and the value being the value itself
                        NSArray *ordereredExisting = [[self valueForKeyPath:relationshipName] allObjects];
                        NSArray *orderedExistingKeys = [ordereredExisting valueForKey:destinationEntityUniqueIdPropertyName];
                        NSCountedSet *uniqueExistingKeys = [NSCountedSet setWithArray:orderedExistingKeys];
                        if(uniqueExistingKeys.count != orderedExistingKeys.count) {
                            //this means that there is more than one object in the existing set of children
                            //with a given value for the ID property - this is bad, since it
                            //violates our invariant that the ID property must be unique and
                            //a way to identify a given object in the collection.
                            NSSet *duplicateIds = [uniqueExistingKeys objectsPassingTest:^BOOL(id obj, BOOL *stop) {
                                return [uniqueExistingKeys countForObject:obj] > 1;
                            }];
                            NSLog(@"WARNING! The existing values in relationship %@ on entity %@ contains mutiple values for the supposedly unique key %@. This will cause undefined behavior on the target NSManagedObject. (The likeliest result is that one of the inputs is completely ignored.) Keys with non-unique occurences - %@", relationshipName, self.entity.name, destinationEntityUniqueIdPropertyName, duplicateIds);
                        }
                        
                        NSDictionary *existingById = [NSDictionary dictionaryWithObjects:ordereredExisting forKeys:orderedExistingKeys];
                        
                        NSMutableArray *newValues = [NSMutableArray arrayWithCapacity:inputValues.count];
                        //now iterate through the input and set the values
                        for(NSDictionary *inputValue in inputValues) {
                            NSManagedObject *child = nil;
                            id inputIdentifierPropertyVal = [inputValue objectForKey:destinationEntityUniqueIdPropertyName];
                            if (inputIdentifierPropertyVal == nil) {
                                NSLog(@"Could not get identifier property from child object - assuming that the object is an insert.");
                                NSLog(@"Note - this may or may not cause leaks in your object graph.");
                            } else {
                                child = [existingById objectForKey:inputIdentifierPropertyVal];
                            }
                            if(child == nil) {
                                
                                //if this is a many/many relationship, we can re-use an existing object in the context
                                //in this collection (if present)
                                if (isManyToMany && inputIdentifierPropertyVal != nil) {
                                    //try and find it in the context - it may exist
                                    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
                                    fetch.entity = relationship.destinationEntity;
                                    fetch.predicate = [NSPredicate predicateWithFormat:@"%K == %@", destinationEntityUniqueIdPropertyName, inputIdentifierPropertyVal];
                                    NSArray *results = [self.managedObjectContext executeFetchRequest:fetch error:error];
                                    if (*error != nil) {
                                        return NO;
                                    }
                                    if (results.count > 1) {
                                        //                                        DLog(@"More than one object returned for entity named %@ with attribute %@ valued %@. Selecting random object.", relationship.destinationEntity.name, collectionIdName, inputIdentifierPropertyVal);
                                    }
                                    child = [results lastObject];
                                }
                                if (child == nil) {
                                    //                                    DLog(@"Creating new instance of %@ for relationship %@", relationship.destinationEntity.name, relationshipName);
                                    //just create a new object
                                    child = [[NSManagedObject alloc] initWithEntity:relationship.destinationEntity insertIntoManagedObjectContext:self.managedObjectContext];
                                    if(child == nil) {
                                        NSString *errorMessage = [NSString stringWithFormat:@"Could not allocate object of type %@", relationship.destinationEntity.name];
                                        *error = [NSError errorWithDomain:kPMDataUtilsErrorDomain
                                                                     code:kPMDataUtilsGeneral
                                                                 userInfo:@{NSLocalizedDescriptionKey : errorMessage}];
                                        return NO;
                                    }
                                }
                            } else {
                                //                                DLog(@"Found existing object for relationship %@", relationshipName);
                            }
                            //okay - update the child with the properties from the dictionary, and associate it to the relationship
                            if(![child setValuesAndRelationshipsForKeysWithDictionary:inputValue error:error]) {
                                return NO;
                            }
                            [newValues addObject:child];
                        }
                        
                        //okay now do the unrelate/deletes
                        //to do this, we find all objects that are in the existing collection but not in the input
                        if (relationship.deleteRule == NSCascadeDeleteRule) {
                            //only delete if this object 'owns' the children
                            NSMutableSet *existingObjectIds = [NSMutableSet setWithArray:[ordereredExisting valueForKeyPath:@"objectID"]];
                            [existingObjectIds minusSet:[NSSet setWithArray:[newValues valueForKeyPath:@"objectID"]]];
                            //                            DLog(@"Deleting %i orphaned objects of type %@.", existingObjectIds.count, relationship.destinationEntity.name);
                            for(NSManagedObjectID *objectId in existingObjectIds) {
                                NSManagedObject *obj = [self.managedObjectContext objectWithID:objectId];
                                [self.managedObjectContext deleteObject:obj];
                            }
                        }
                        
                        //set the new relationship value
                        if(relationship.isOrdered) {
                            [self setValue:[NSOrderedSet orderedSetWithArray:newValues] forKeyPath:relationshipName];
                        } else {
                            [self setValue:[NSSet setWithArray:newValues] forKeyPath:relationshipName];
                        }
                        
                    } else {
                        //                        DLog(@"Can't identify collection for relationship %@ - just recreating.", relationshipName);
                        id existingChildren = nil;
                        if(relationship.isOrdered) {
                            existingChildren = [self mutableOrderedSetValueForKeyPath:relationshipName];
                        } else {
                            existingChildren = [self mutableSetValueForKeyPath:relationshipName];
                        }
                        //no way to identify child objects. this means they all get removed and optionally deleted
                        if(relationship.deleteRule == NSCascadeDeleteRule) {
                            //since it's a cascade delete, we can assume that this object 'owns' it's children so delete them
                            for (NSManagedObject *child in existingChildren) {
                                [child.managedObjectContext deleteObject:child];
                            }
                        }
                        //remove them from the relationship
                        [existingChildren removeAllObjects];
                        //now create and insert the new objects
                        for (NSDictionary *inputChild in inputValues) {
                            NSManagedObject *newChild = [[NSManagedObject alloc] initWithEntity:relationship.destinationEntity insertIntoManagedObjectContext:self.managedObjectContext];
                            if(newChild == nil) {
                                NSLog(@"Could not allocate object of type %@", relationship.destinationEntity.name);
                            }
                            if(![newChild setValuesAndRelationshipsForKeysWithDictionary:inputChild error:error]) {
                                return NO;
                            }
                            [existingChildren addObject:newChild];
                        }
                    }
                }
            }
        }
    }
    @catch(NSException *e) {
        NSLog(@"Could not set values on %@ due to exception %@", [[self entity] name], e.reason);
        return NO;
    }
    return YES;
}

@end

