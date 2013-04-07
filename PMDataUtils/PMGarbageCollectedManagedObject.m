//
//  NSGarbageCollectedManagedObject.m
//
//  Created by David Pratt on 2/21/13.
//
//

#import "PMGarbageCollectedManagedObject.h"

@implementation PMGarbageCollectedManagedObject

- (void)willSave {
    
    if(self.isDeleted) {
        //no need to check for garbage
        return;
    }

    BOOL shouldDelete = YES;

    NSDictionary *relationshipDict = self.entity.relationshipsByName;
    for (NSString *relationshipName in relationshipDict) {
        NSRelationshipDescription *relationship = [relationshipDict objectForKey:relationshipName];
        
        //only check for pointers to objects we don't 'own'
        //it's assumed that a cascade relationship means that this object
        //is responsible for the existence and management of a child object
        if (relationship.deleteRule != NSCascadeDeleteRule) {
            //examine the relationship and see if there are any active pointers
            if(relationship.isToMany) {
                NSSet *values = [self valueForKey:relationshipName];
                if(values.count != 0) {
                    shouldDelete = NO;
                    break;
                }
            } else {
                id child = [self valueForKey:relationshipName];
                if(child != nil) {
                    shouldDelete = NO;
                    break;
                }
            }
        }
    }
    
    if(shouldDelete) {
        //remove ourselves
//        NSLog(@"Object of type %@ being garbage collected!", self.entity.name);
        [self.managedObjectContext deleteObject:self];
    }
}

@end
