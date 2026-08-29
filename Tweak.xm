#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <spawn.h>
#import <sys/stat.h>
#import <unistd.h>

extern char **environ;

static NSString * const TLRoot = @"/var/mobile/Library/TouchLooper";
static NSString * const TLFlag = @"/var/mobile/Library/TouchLooper/recording.flag";
static NSString * const TLStart = @"/var/mobile/Library/TouchLooper/start.txt";
static NSString * const TLMacro = @"/var/mobile/Library/TouchLooper/current.jsonl";
static NSString * const TLStop = @"/var/mobile/Library/TouchLooper/stop.flag";
static NSString * const TLPrefs = @"/var/mobile/Library/TouchLooper/prefs.plist";

static void TLEnsureStorage(void) {
    mkdir([TLRoot fileSystemRepresentation], 0777);
    chmod([TLRoot fileSystemRepresentation], 0777);
    NSString *macros = [TLRoot stringByAppendingPathComponent:@"macros"];
    mkdir([macros fileSystemRepresentation], 0777);
    chmod([macros fileSystemRepresentation], 0777);
}

static BOOL TLRecordingEnabled(void) {
    return access([TLFlag fileSystemRepresentation], F_OK) == 0;
}

static double TLRecordingStart(void) {
    NSString *s = [NSString stringWithContentsOfFile:TLStart encoding:NSUTF8StringEncoding error:nil];
    return s.doubleValue;
}

static void TLAppendJSON(NSDictionary *obj) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
    if (!data) return;
    NSMutableData *line = [data mutableCopy];
    [line appendData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
    int fd = open([TLMacro fileSystemRepresentation], O_WRONLY | O_CREAT | O_APPEND, 0666);
    if (fd < 0) return;
    write(fd, line.bytes, line.length);
    close(fd);
    chmod([TLMacro fileSystemRepresentation], 0666);
}

static NSMutableDictionary<NSString *, NSNumber *> *TLFingerMap;
static NSInteger TLNextFinger = 1;

static NSInteger TLFingerForTouch(UITouch *touch, BOOL create) {
    if (!TLFingerMap) TLFingerMap = [NSMutableDictionary dictionary];
    NSString *key = [NSString stringWithFormat:@"%p", touch];
    NSNumber *existing = TLFingerMap[key];
    if (existing) return existing.integerValue;
    if (!create) return 1;
    NSInteger finger = TLNextFinger++;
    if (TLNextFinger > 19) TLNextFinger = 1;
    TLFingerMap[key] = @(finger);
    return finger;
}

%hook UIApplication
- (void)sendEvent:(UIEvent *)event {
    if (TLRecordingEnabled() && event.type == UIEventTypeTouches) {
        double start = TLRecordingStart();
        if (start > 0) {
            for (UITouch *touch in event.allTouches) {
                NSString *phase = nil;
                switch (touch.phase) {
                    case UITouchPhaseBegan: phase = @"down"; break;
                    case UITouchPhaseMoved: phase = @"move"; break;
                    case UITouchPhaseEnded: phase = @"up"; break;
                    case UITouchPhaseCancelled: phase = @"up"; break;
                    default: break;
                }
                if (!phase) continue;

                UIWindow *window = touch.window ?: self.keyWindow;
                CGPoint p = [touch locationInView:window];
                CGSize size = window.bounds.size;
                CGFloat nx = size.width > 0 ? p.x / size.width : 0;
                CGFloat ny = size.height > 0 ? p.y / size.height : 0;
                nx = MAX(0, MIN(1, nx));
                ny = MAX(0, MIN(1, ny));

                BOOL began = touch.phase == UITouchPhaseBegan;
                NSInteger finger = TLFingerForTouch(touch, began);
                double now = CACurrentMediaTime();

                TLAppendJSON(@{
                    @"t": @(MAX(0, now - start)),
                    @"phase": phase,
                    @"finger": @(finger),
                    @"nx": @(nx),
                    @"ny": @(ny),
                    @"bundle": NSBundle.mainBundle.bundleIdentifier ?: @"unknown"
                });

                if (touch.phase == UITouchPhaseEnded || touch.phase == UITouchPhaseCancelled) {
                    NSString *key = [NSString stringWithFormat:@"%p", touch];
                    [TLFingerMap removeObjectForKey:key];
                }
            }
        }
    }
    %orig;
}
%end

@interface TLPassWindow : UIWindow
@property(nonatomic, weak) UIView *panel;
@end
@implementation TLPassWindow
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (!self.panel || self.panel.hidden) return NO;
    CGPoint local = [self.panel convertPoint:point fromView:self];
    return [self.panel pointInside:local withEvent:event];
}
@end

@interface TLController : NSObject
@property(nonatomic, strong) TLPassWindow *window;
@property(nonatomic, strong) UIView *panel;
@property(nonatomic, strong) UILabel *status;
@end

@implementation TLController

+ (instancetype)shared {
    static TLController *x;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ x = [TLController new]; });
    return x;
}

- (UIButton *)button:(NSString *)title action:(SEL)action frame:(CGRect)frame {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = frame;
    b.layer.cornerRadius = 10;
    b.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)install {
    TLEnsureStorage();
    CGRect screen = UIScreen.mainScreen.bounds;
    self.window = [[TLPassWindow alloc] initWithFrame:screen];
    self.window.windowLevel = UIWindowLevelAlert + 1000;
    self.window.backgroundColor = UIColor.clearColor;
    self.window.rootViewController = [UIViewController new];

    self.panel = [[UIView alloc] initWithFrame:CGRectMake(18, 120, 176, 190)];
    self.panel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.92];
    self.panel.layer.cornerRadius = 18;
    self.panel.layer.borderWidth = 1;
    self.panel.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.15].CGColor;
    self.window.panel = self.panel;
    [self.window.rootViewController.view addSubview:self.panel];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(14, 8, 148, 24)];
    title.text = @"TouchLooper";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:17];
    title.textAlignment = NSTextAlignmentCenter;
    [self.panel addSubview:title];

    self.status = [[UILabel alloc] initWithFrame:CGRectMake(10, 34, 156, 20)];
    self.status.text = @"Ready";
    self.status.textColor = [UIColor colorWithWhite:0.8 alpha:1];
    self.status.font = [UIFont systemFontOfSize:12];
    self.status.textAlignment = NSTextAlignmentCenter;
    [self.panel addSubview:self.status];

    [self.panel addSubview:[self button:@"● REC" action:@selector(record) frame:CGRectMake(10, 62, 74, 42)]];
    [self.panel addSubview:[self button:@"■ STOP" action:@selector(stop) frame:CGRectMake(92, 62, 74, 42)]];
    [self.panel addSubview:[self button:@"▶ PLAY" action:@selector(play) frame:CGRectMake(10, 112, 156, 42)]];
    [self.panel addSubview:[self button:@"SAVE" action:@selector(save) frame:CGRectMake(10, 160, 74, 22)]];
    [self.panel addSubview:[self button:@"HIDE" action:@selector(hide) frame:CGRectMake(92, 160, 74, 22)]];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
    [title addGestureRecognizer:pan];
    title.userInteractionEnabled = YES;

    self.window.hidden = NO;
}

- (void)drag:(UIPanGestureRecognizer *)g {
    CGPoint tr = [g translationInView:self.window];
    CGPoint c = self.panel.center;
    c.x += tr.x; c.y += tr.y;
    CGFloat hw = self.panel.bounds.size.width/2.0, hh = self.panel.bounds.size.height/2.0;
    c.x = MAX(hw, MIN(self.window.bounds.size.width-hw, c.x));
    c.y = MAX(hh, MIN(self.window.bounds.size.height-hh, c.y));
    self.panel.center = c;
    [g setTranslation:CGPointZero inView:self.window];
}

- (void)record {
    TLEnsureStorage();
    unlink([TLStop fileSystemRepresentation]);
    unlink([TLMacro fileSystemRepresentation]);
    self.status.text = @"Starting…";
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSString *start = [NSString stringWithFormat:@"%.9f", CACurrentMediaTime()];
        [start writeToFile:TLStart atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [@"1" writeToFile:TLFlag atomically:YES encoding:NSUTF8StringEncoding error:nil];
        chmod([TLFlag fileSystemRepresentation], 0666);
        self.status.text = @"● Recording";
    });
}

- (void)stop {
    unlink([TLFlag fileSystemRepresentation]);
    [@"1" writeToFile:TLStop atomically:YES encoding:NSUTF8StringEncoding error:nil];
    chmod([TLStop fileSystemRepresentation], 0666);
    self.status.text = @"Stopped";
}

- (NSDictionary *)prefs {
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:TLPrefs];
    return p ?: @{@"repeat":@1, @"speed":@1.0, @"interval":@0.0};
}

- (void)runHelperWithArgs:(NSArray<NSString *> *)args {
    NSString *helper = @"/var/jb/usr/local/bin/touchlooper-helper";
    if (![[NSFileManager defaultManager] fileExistsAtPath:helper]) {
        self.status.text = @"Helper missing";
        return;
    }
    NSMutableArray *all = [NSMutableArray arrayWithObject:helper];
    [all addObjectsFromArray:args];
    char **argv = calloc(all.count + 1, sizeof(char *));
    for (NSUInteger i=0; i<all.count; i++) argv[i] = strdup([all[i] UTF8String]);
    pid_t pid = 0;
    int result = posix_spawn(&pid, helper.fileSystemRepresentation, NULL, NULL, argv, environ);
    for (NSUInteger i=0; i<all.count; i++) free(argv[i]);
    free(argv);
    self.status.text = result == 0 ? @"▶ Playing" : @"Launch failed";
}

- (void)play {
    unlink([TLFlag fileSystemRepresentation]);
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Playback" message:@"Set repeats, speed and delay between loops." preferredStyle:UIAlertControllerStyleAlert];
    NSDictionary *p = [self prefs];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){ f.placeholder=@"Repeat count"; f.keyboardType=UIKeyboardTypeNumberPad; f.text=[p[@"repeat"] stringValue]; }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){ f.placeholder=@"Speed (0.1 - 10)"; f.keyboardType=UIKeyboardTypeDecimalPad; f.text=[p[@"speed"] stringValue]; }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){ f.placeholder=@"Loop delay seconds"; f.keyboardType=UIKeyboardTypeDecimalPad; f.text=[p[@"interval"] stringValue]; }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Play" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){
        NSInteger repeat = MAX(1, [a.textFields[0].text integerValue]);
        double speed = MIN(10.0, MAX(0.1, [a.textFields[1].text doubleValue]));
        double interval = MAX(0.0, [a.textFields[2].text doubleValue]);
        NSDictionary *np = @{@"repeat":@(repeat), @"speed":@(speed), @"interval":@(interval)};
        [np writeToFile:TLPrefs atomically:YES];
        unlink([TLStop fileSystemRepresentation]);
        [self runHelperWithArgs:@[@"play", TLMacro, [NSString stringWithFormat:@"%ld", (long)repeat], [NSString stringWithFormat:@"%.4f", speed], [NSString stringWithFormat:@"%.4f", interval]]];
    }]];
    [self.window.rootViewController presentViewController:a animated:YES completion:nil];
}

- (void)save {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Save macro" message:@"Give this recording a name." preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){ f.placeholder=@"Macro name"; }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){
        NSString *name = a.textFields.firstObject.text ?: @"macro";
        NSCharacterSet *bad = [[NSCharacterSet alphanumericCharacterSet] invertedSet];
        name = [[name componentsSeparatedByCharactersInSet:bad] componentsJoinedByString:@"_"];
        if (name.length == 0) name = @"macro";
        NSString *dest = [NSString stringWithFormat:@"%@/macros/%@.jsonl", TLRoot, name];
        [[NSFileManager defaultManager] removeItemAtPath:dest error:nil];
        BOOL ok = [[NSFileManager defaultManager] copyItemAtPath:TLMacro toPath:dest error:nil];
        self.status.text = ok ? [NSString stringWithFormat:@"Saved %@", name] : @"Nothing to save";
    }]];
    [self.window.rootViewController presentViewController:a animated:YES completion:nil];
}

- (void)hide { self.panel.hidden = YES; }
@end

%ctor {
    TLEnsureStorage();
    if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[TLController shared] install];
        });
    }
}
