// PetitLyrics, reimplemented from EeveeSpotify's PetitLyricsRepository.swift (GPL-3.0): the
// Japanese catalog's form-posted API, answered in XML. A search by title and artist gives a
// lyrics id, the id gives the lines — word-stamped where the catalog has them, plain text where
// it has only those. A line's time is its first word's, so the timing is by the line here.
#import "Core/SGCore.h"
#import "LyricsSources.h"

static NSString *const kEndpoint = @"https://p1.petitlyrics.com/api/GetPetitLyricsData.php";

typedef NS_ENUM(NSInteger, SGPetitType) {
    SGPetitTypePlain = 1,
    SGPetitTypeLinesSynced = 2,
    SGPetitTypeWordsSynced = 3,
};

#pragma mark - the XML as a tree

@interface SGPetitNode : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *attributes;
@property (nonatomic, copy) NSMutableString *text;
@property (nonatomic, strong) NSMutableArray<SGPetitNode *> *children;
@end

@implementation SGPetitNode
- (instancetype)init {
    if (!(self = [super init])) return nil;
    _text = [NSMutableString string];
    _children = [NSMutableArray array];
    return self;
}
// Every node of `name` under this one, this one included, deepest first never — a plain preorder.
- (void)collect:(NSString *)name into:(NSMutableArray<SGPetitNode *> *)into {
    if ([self.name isEqualToString:name]) [into addObject:self];
    for (SGPetitNode *child in self.children) [child collect:name into:into];
}
- (SGPetitNode *)first:(NSString *)name {
    if ([self.name isEqualToString:name]) return self;
    for (SGPetitNode *child in self.children) {
        SGPetitNode *found = [child first:name];
        if (found) return found;
    }
    return nil;
}
- (NSString *)textOf:(NSString *)name {
    SGPetitNode *node = [self first:name];
    return node ? [node.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : nil;
}
@end

@interface SGPetitParser : NSObject <NSXMLParserDelegate>
@property (nonatomic, strong) SGPetitNode *root;
@end

@implementation SGPetitParser {
    NSMutableArray<SGPetitNode *> *_stack;
}
- (SGPetitNode *)parse:(NSData *)xml {
    _stack = [NSMutableArray array];
    NSXMLParser *parser = [[NSXMLParser alloc] initWithData:xml];
    parser.delegate = self;
    if (![parser parse]) return nil;
    return self.root;
}
- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)element namespaceURI:(NSString *)uri
    qualifiedName:(NSString *)name attributes:(NSDictionary<NSString *, NSString *> *)attributes {
    SGPetitNode *node = [SGPetitNode new];
    node.name = element;
    node.attributes = attributes;
    if (_stack.count) [[_stack.lastObject children] addObject:node];
    [_stack addObject:node];
}
- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
    [[_stack.lastObject text] appendString:string];
}
- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)element namespaceURI:(NSString *)uri qualifiedName:(NSString *)name {
    SGPetitNode *node = _stack.lastObject;
    [_stack removeLastObject];
    if (!_stack.count) self.root = node;
}
@end

#pragma mark - asking

static NSString *formEncode(NSDictionary<NSString *, NSString *> *fields) {
    static NSMutableCharacterSet *allowed;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        allowed = [NSCharacterSet.URLQueryAllowedCharacterSet mutableCopy];
        [allowed removeCharactersInString:@"&=+?"];
    });
    NSMutableArray<NSString *> *pairs = [NSMutableArray array];
    [fields enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSString *value, BOOL *stop) {
        [pairs addObject:[NSString stringWithFormat:@"%@=%@",
                          [name stringByAddingPercentEncodingWithAllowedCharacters:allowed],
                          [value stringByAddingPercentEncodingWithAllowedCharacters:allowed]]];
    }];
    return [pairs componentsJoinedByString:@"&"];
}

static void post(NSDictionary<NSString *, NSString *> *fields, void (^done)(SGPetitNode *song)) {
    NSMutableDictionary<NSString *, NSString *> *body = [fields mutableCopy];
    body[@"clientAppId"] = @"p1110417";
    body[@"terminalType"] = @"10";
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kEndpoint]
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:10];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [formEncode(body) dataUsingEncoding:NSUTF8StringEncoding];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *reply, NSError *error) {
        SGLyricsNoteReply(reply, error);
        SGPetitNode *root = nil;
        NSInteger status = [reply isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)reply).statusCode : 0;
        if (!error && status >= 200 && status < 300 && data.length) root = [[SGPetitParser new] parse:data];
        SGPetitNode *song = [root first:@"song"];
        dispatch_async(dispatch_get_main_queue(), ^{ done(song); });
    }] resume];
}

// The word-stamped lyricsData as lines: each line's first word's starttime is its start, the
// linestring its text. nil when nothing in it is timed.
static SGLyricsResult *syncedResult(NSData *xml) {
    SGPetitNode *root = [[SGPetitParser new] parse:xml];
    if (!root) return nil;
    NSMutableArray<SGPetitNode *> *lines = [NSMutableArray array];
    [root collect:@"line" into:lines];
    NSMutableArray<NSNumber *> *starts = [NSMutableArray array];
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    for (SGPetitNode *line in lines) {
        NSString *text = [line textOf:@"linestring"];
        SGPetitNode *word = [line first:@"word"];
        NSInteger at = word.attributes[@"starttime"] ? (NSInteger)[word.attributes[@"starttime"] integerValue] : -1;
        if (at < 0) continue;
        [starts addObject:@(at)];
        [texts addObject:text.length ? text : @"♪"];
    }
    if (!starts.count) return nil;
    NSArray<SGKaraokeLine *> *lines_ = SGKaraokeEstimatedLines(starts, texts);
    SGLyricsResult *result = [SGLyricsResult new];
    result.synced = YES;
    result.karaokeLines = lines_;
    NSArray<NSNumber *> *pageStarts;
    NSArray<NSString *> *pageTexts;
    SGLyricsPageLines(lines_, &pageStarts, &pageTexts);
    result.starts = pageStarts;
    result.texts = pageTexts;
    return result;
}

static SGLyricsResult *plainResult(NSData *data) {
    NSString *plain = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!plain.length) return nil;
    NSMutableArray<NSNumber *> *starts = [NSMutableArray array];
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    for (NSString *row in [plain componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *trimmed = [row stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        [starts addObject:@0];
        [texts addObject:trimmed.length ? trimmed : @"♪"];
    }
    if (!texts.count) return nil;
    SGLyricsResult *result = [SGLyricsResult new];
    result.starts = starts;
    result.texts = texts;
    result.karaokeLines = SGKaraokeStaticLines(texts);
    return result;
}

SGLyricsAsk SGPetitLyricsAsk = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *result)) {
    if (!query.title.length || !query.artist.length) {
        SGLog(@"petitlyrics: nothing to search with for %@", query.trackID);
        done(nil);
        return;
    }
    post(@{@"key_title": query.title, @"key_artist": SGLyricsLeadArtist(query.artist), @"max_count": @"1"}, ^(SGPetitNode *found) {
        NSString *lyricsId = [found textOf:@"lyricsId"];
        if (!lyricsId.length) {
            SGLog(@"petitlyrics: no song for %@ by %@", query.title, query.artist);
            done(nil);
            return;
        }
        // As the reference does: line-synced sheets are read as plain text, word-stamped ones
        // with their stamps, everything else as whatever the search said is there.
        SGPetitType available = (SGPetitType)[[found textOf:@"availableLyricsType"] integerValue];
        SGPetitType ask = available == SGPetitTypeLinesSynced ? SGPetitTypePlain : available;
        post(@{@"key_lyricsId": lyricsId, @"lyricsType": @(ask).stringValue}, ^(SGPetitNode *song) {
            SGPetitType type = (SGPetitType)[[song textOf:@"lyricsType"] integerValue];
            NSString *encoded = [song textOf:@"lyricsData"];
            NSData *data = encoded.length ? [[NSData alloc] initWithBase64EncodedString:encoded options:NSDataBase64DecodingIgnoreUnknownCharacters] : nil;
            SGLyricsResult *result = nil;
            if (data.length) {
                if (type == SGPetitTypeWordsSynced) result = syncedResult(data);
                else if (type == SGPetitTypePlain) result = plainResult(data);
            }
            SGLog(@"petitlyrics: %@ by %@ gave %@", query.title, query.artist,
                  !result ? @"nothing" : result.synced
                      ? [NSString stringWithFormat:@"%lu timed lines", (unsigned long)result.karaokeLines.count]
                      : [NSString stringWithFormat:@"%lu untimed lines", (unsigned long)result.texts.count]);
            done(result);
        });
    });
};
