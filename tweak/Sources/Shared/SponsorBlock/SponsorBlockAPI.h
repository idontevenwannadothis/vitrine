// Fetches the segments of one episode from the SponsorBlock database; the completion runs on an
// arbitrary queue. A 404 (nothing filed) is an empty answer, not an error.
#import "SponsorBlock.h"

void SGSponsorFetchSegments(NSString *episodeID, NSArray<NSString *> *categories,
                            void (^completion)(NSArray<SGSponsorSegment *> *segments, NSError *error));
