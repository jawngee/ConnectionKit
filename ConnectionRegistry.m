//
//  ConnectionRegistry.m
//  Connection
//
//  Created by Greg Hulands on 15/11/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "ConnectionRegistry.h"
#import "CKHostCategory.h"
#import "CKBonjourCategory.h"
#import "CKHost.h"

static NSLock *sRegistryLock = nil;
static BOOL sRegistryCanInit = NO;
static ConnectionRegistry *sRegistry = nil;

NSString *CKRegistryNotification = @"CKRegistryNotification";
NSString *CKRegistryChangedNotification = @"CKRegistryChangedNotification";

@interface ConnectionRegistry (Private)
- (void)otherProcessChanged:(NSNotification *)notification;
- (NSString *)databaseFile;
@end

@implementation ConnectionRegistry

+ (void)load
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	sRegistryLock = [[NSLock alloc] init];
	
	[pool release];
}

+ (id)sharedRegistry
{
	if (!sRegistry)
	{
		[sRegistryLock lock];
		sRegistryCanInit = YES;
		sRegistry = [[ConnectionRegistry alloc] init];
		sRegistryCanInit = NO;
	}
	return sRegistry;
}

- (id)init
{
	if (!sRegistryCanInit)
	{
		return nil;
	}
	if ((self = [super init]))
	{
		myLock = [[NSLock alloc] init];
		myCenter = [NSDistributedNotificationCenter defaultCenter];
		myConnections = [[NSMutableArray alloc] init];
		myBonjour = [[CKBonjourCategory alloc] init];
		[myConnections addObject:myBonjour];
		
		[myCenter addObserver:self
					 selector:@selector(otherProcessChanged:)
						 name:CKRegistryNotification
					   object:nil];
		NSArray *hosts = [NSKeyedUnarchiver unarchiveObjectWithFile:[self databaseFile]];
		[myConnections addObjectsFromArray:hosts];
		NSEnumerator *e = [hosts objectEnumerator];
		id cur;
		
		while ((cur = [e nextObject]))
		{
			if ([cur isKindOfClass:[CKHostCategory class]])
			{
				[[NSNotificationCenter defaultCenter] addObserver:self
														 selector:@selector(changed:)
															 name:CKHostCategoryChanged
														   object:cur];
			}
			else
			{
				[[NSNotificationCenter defaultCenter] addObserver:self
														 selector:@selector(changed:)
															 name:CKHostChanged
														   object:cur];
			}
		}
		
	}
	return self;
}

- (void)dealloc
{
	[myBonjour release];
	[myLock release];
	[myConnections release];
	
	[super dealloc];
}

- (oneway void)release
{
	
}

- (id)autorelease
{
	return self;
}

- (id)retain
{
	return self;
}

- (NSString *)databaseFile
{
	return [[[NSHomeDirectory() stringByAppendingPathComponent:@"Library"] stringByAppendingPathComponent:@"Preferences"] stringByAppendingPathComponent:@"com.connectionkit.registry"];
}

- (void)otherProcessChanged:(NSNotification *)notification
{
	if ([[NSProcessInfo processInfo] processIdentifier] != [[notification object] intValue])
	{
		[self willChangeValueForKey:@"connections"];
		[myConnections removeAllObjects];
		[myConnections addObject:myBonjour];
		NSArray *hosts = [NSKeyedUnarchiver unarchiveObjectWithFile:[self databaseFile]];
		[myConnections addObjectsFromArray:hosts];
		NSEnumerator *e = [hosts objectEnumerator];
		id cur;
		
		while ((cur = [e nextObject]))
		{
			if ([cur isKindOfClass:[CKHostCategory class]])
			{
				[[NSNotificationCenter defaultCenter] addObserver:self
														 selector:@selector(changed:)
															 name:CKHostCategoryChanged
														   object:cur];
			}
			else
			{
				[[NSNotificationCenter defaultCenter] addObserver:self
														 selector:@selector(changed:)
															 name:CKHostChanged
														   object:cur];
			}
		}
		[self didChangeValueForKey:@"connections"];
	}
}

- (void)changed:(NSNotification *)notification
{
	//write out the db to disk
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *lockPath = @"/tmp/connection.registry.lock";
	
	if ([fm fileExistsAtPath:lockPath])
	{
		[self performSelector:_cmd withObject:nil afterDelay:0.0];
		return;
	}
	
	[fm createFileAtPath:lockPath contents:[NSData data] attributes:nil];
	[myConnections removeObject:myBonjour];
	[NSKeyedArchiver archiveRootObject:myConnections toFile:[self databaseFile]];
	[myConnections addObject:myBonjour];
	[fm removeFileAtPath:lockPath handler:nil];
	
	NSString *pid = [NSString stringWithFormat:@"%d", [[NSProcessInfo processInfo] processIdentifier]];
	[myCenter postNotificationName:CKRegistryNotification object:pid userInfo:nil];
	[[NSNotificationCenter defaultCenter] postNotificationName:CKRegistryChangedNotification object:nil];
}

- (void)addCategory:(CKHostCategory *)category
{
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(changed:)
												 name:CKHostCategoryChanged
											   object:category];
	[self willChangeValueForKey:@"connections"];
	[myConnections addObject:category];
	[self didChangeValueForKey:@"connections"];
	[self changed:nil];
}

- (void)removeCategory:(CKHostCategory *)category
{
	[[NSNotificationCenter defaultCenter] removeObserver:self
													name:CKHostCategoryChanged
												  object:category];
	[self willChangeValueForKey:@"connections"];
	[myConnections removeObject:category];
	[self didChangeValueForKey:@"connections"];
	[self changed:nil];
}

- (void)addHost:(CKHost *)connection
{
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(changed:)
												 name:CKHostChanged
											   object:connection];
	[self willChangeValueForKey:@"connections"];
	[myConnections addObject:connection];
	[self didChangeValueForKey:@"connections"];
	[self changed:nil];
}

- (void)removeHost:(CKHost *)connection
{
	[[NSNotificationCenter defaultCenter] removeObserver:self
													name:CKHostChanged
												  object:connection];
	[self willChangeValueForKey:@"connections"];
	[myConnections removeObject:connection];
	[self didChangeValueForKey:@"connections"];
	[self changed:nil];
}

- (NSArray *)connections
{
	return [NSArray arrayWithArray:myConnections];
}

@end