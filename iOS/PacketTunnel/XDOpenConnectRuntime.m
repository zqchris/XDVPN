#import "XDOpenConnectRuntime.h"

#import <arpa/inet.h>
#import <dlfcn.h>
#import <errno.h>
#import <fcntl.h>
#import <netinet/in.h>
#import <stdarg.h>
#import <sys/socket.h>
#import <unistd.h>

static NSString *const XDOpenConnectErrorDomain = @"com.kafeifei.xdvpn.ios.OpenConnectRuntime";
static const char XDOpenConnectCancelCommand = 'x';

#define OC_FORM_OPT_TEXT 1
#define OC_FORM_OPT_PASSWORD 2
#define PRG_ERR 0
#define PRG_DEBUG 2
#define RECONNECT_INTERVAL_MIN 10

struct openconnect_info;
struct oc_form_opt {
    struct oc_form_opt *next;
    int type;
    char *name;
    char *label;
    char *_value;
    unsigned int flags;
    void *reserved;
};
struct oc_form_opt_select {
    struct oc_form_opt form;
    int nr_choices;
    void *choices;
};
struct oc_auth_form {
    char *banner;
    char *message;
    char *error;
    char *auth_id;
    char *method;
    char *action;
    struct oc_form_opt *opts;
    struct oc_form_opt_select *authgroup_opt;
    int authgroup_selection;
};
struct oc_split_include {
    const char *route;
    struct oc_split_include *next;
};
struct oc_ip_info {
    const char *addr;
    const char *netmask;
    const char *addr6;
    const char *netmask6;
    const char *dns[3];
    const char *nbns[3];
    const char *domain;
    const char *proxy_pac;
    int mtu;
    struct oc_split_include *split_dns;
    struct oc_split_include *split_includes;
    struct oc_split_include *split_excludes;
    char *gateway_addr;
};
struct oc_vpn_option {
    char *option;
    char *value;
    struct oc_vpn_option *next;
};
struct oc_stats {
    uint64_t tx_pkts;
    uint64_t tx_bytes;
    uint64_t rx_pkts;
    uint64_t rx_bytes;
};

typedef int (*xd_oc_validate_peer_cert_vfn)(void *privdata, const char *reason);
typedef int (*xd_oc_write_new_config_vfn)(void *privdata, const char *buf, int buflen);
typedef int (*xd_oc_process_auth_form_vfn)(void *privdata, struct oc_auth_form *form);
typedef void (*xd_oc_progress_vfn)(void *privdata, int level, const char *fmt, ...);
typedef void (*xd_oc_protect_socket_vfn)(void *privdata, int fd);
typedef void (*xd_oc_setup_tun_vfn)(void *privdata);
typedef void (*xd_oc_stats_vfn)(void *privdata, const struct oc_stats *stats);

typedef int (*xd_openconnect_init_ssl_fn)(void);
typedef struct openconnect_info *(*xd_openconnect_vpninfo_new_fn)(
    const char *useragent,
    xd_oc_validate_peer_cert_vfn validate_peer_cert,
    xd_oc_write_new_config_vfn write_new_config,
    xd_oc_process_auth_form_vfn process_auth_form,
    xd_oc_progress_vfn progress,
    void *privdata
);
typedef void (*xd_openconnect_vpninfo_free_fn)(struct openconnect_info *vpninfo);
typedef int (*xd_openconnect_set_protocol_fn)(struct openconnect_info *vpninfo, const char *protocol);
typedef int (*xd_openconnect_set_reported_os_fn)(struct openconnect_info *vpninfo, const char *os);
typedef int (*xd_openconnect_set_mobile_info_fn)(
    struct openconnect_info *vpninfo,
    const char *mobile_platform_version,
    const char *mobile_device_type,
    const char *mobile_device_uniqueid
);
typedef int (*xd_openconnect_parse_url_fn)(struct openconnect_info *vpninfo, const char *url);
typedef int (*xd_openconnect_obtain_cookie_fn)(struct openconnect_info *vpninfo);
typedef int (*xd_openconnect_make_cstp_connection_fn)(struct openconnect_info *vpninfo);
typedef int (*xd_openconnect_setup_dtls_fn)(struct openconnect_info *vpninfo, int dtls_attempt_period);
typedef int (*xd_openconnect_setup_cmd_pipe_fn)(struct openconnect_info *vpninfo);
typedef int (*xd_openconnect_setup_tun_fd_fn)(struct openconnect_info *vpninfo, int tun_fd);
typedef int (*xd_openconnect_mainloop_fn)(
    struct openconnect_info *vpninfo,
    int reconnect_timeout,
    int reconnect_interval
);
typedef int (*xd_openconnect_get_ip_info_fn)(
    struct openconnect_info *vpninfo,
    const struct oc_ip_info **info,
    const struct oc_vpn_option **cstp_options,
    const struct oc_vpn_option **dtls_options
);
typedef int (*xd_openconnect_set_option_value_fn)(struct oc_form_opt *opt, const char *value);
typedef void (*xd_openconnect_set_protect_socket_handler_fn)(
    struct openconnect_info *vpninfo,
    xd_oc_protect_socket_vfn protect_socket
);
typedef void (*xd_openconnect_set_setup_tun_handler_fn)(
    struct openconnect_info *vpninfo,
    xd_oc_setup_tun_vfn setup_tun
);
typedef void (*xd_openconnect_set_stats_handler_fn)(
    struct openconnect_info *vpninfo,
    xd_oc_stats_vfn stats_handler
);
typedef void (*xd_openconnect_set_loglevel_fn)(struct openconnect_info *vpninfo, int level);
typedef int (*xd_openconnect_disable_ipv6_fn)(struct openconnect_info *vpninfo);

typedef struct {
    void *handle;
    xd_openconnect_init_ssl_fn init_ssl;
    xd_openconnect_vpninfo_new_fn vpninfo_new;
    xd_openconnect_vpninfo_free_fn vpninfo_free;
    xd_openconnect_set_protocol_fn set_protocol;
    xd_openconnect_set_reported_os_fn set_reported_os;
    xd_openconnect_set_mobile_info_fn set_mobile_info;
    xd_openconnect_parse_url_fn parse_url;
    xd_openconnect_obtain_cookie_fn obtain_cookie;
    xd_openconnect_make_cstp_connection_fn make_cstp_connection;
    xd_openconnect_setup_dtls_fn setup_dtls;
    xd_openconnect_setup_cmd_pipe_fn setup_cmd_pipe;
    xd_openconnect_setup_tun_fd_fn setup_tun_fd;
    xd_openconnect_mainloop_fn mainloop;
    xd_openconnect_get_ip_info_fn get_ip_info;
    xd_openconnect_set_option_value_fn set_option_value;
    xd_openconnect_set_protect_socket_handler_fn set_protect_socket_handler;
    xd_openconnect_set_setup_tun_handler_fn set_setup_tun_handler;
    xd_openconnect_set_stats_handler_fn set_stats_handler;
    xd_openconnect_set_loglevel_fn set_loglevel;
    xd_openconnect_disable_ipv6_fn disable_ipv6;
} XDOpenConnectSymbols;

@interface XDOpenConnectRuntime ()
@property (nonatomic, weak) NEPacketTunnelProvider *provider;
@property (nonatomic, strong) NEPacketTunnelFlow *packetFlow;
@property (nonatomic, copy) NSDictionary<NSString *, id> *configuration;
@property (nonatomic, copy) NSString *username;
@property (nonatomic, copy) NSString *password;
@property (nonatomic) BOOL allowUntrustedServerCertificate;
@property (nonatomic, copy) void (^startCompletion)(NSError *_Nullable error);
@property (nonatomic, copy) void (^stopCompletion)(void);
@property (nonatomic) XDOpenConnectSymbols symbols;
@property (nonatomic) struct openconnect_info *vpninfo;
@property (nonatomic) int commandFD;
@property (nonatomic) int openconnectFD;
@property (nonatomic) int packetFlowFD;
@property (nonatomic) dispatch_source_t packetReadSource;
@property (nonatomic) dispatch_queue_t workerQueue;
@property (nonatomic) dispatch_queue_t packetQueue;
@property (nonatomic) BOOL startCompleted;
@property (nonatomic) BOOL stopping;
@end

@implementation XDOpenConnectRuntime

- (instancetype)init {
    self = [super init];
    if (self) {
        _commandFD = -1;
        _openconnectFD = -1;
        _packetFlowFD = -1;
        _workerQueue = dispatch_queue_create("com.kafeifei.xdvpn.openconnect.worker", DISPATCH_QUEUE_SERIAL);
        _packetQueue = dispatch_queue_create("com.kafeifei.xdvpn.openconnect.packetflow", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)dealloc {
    [self closePacketBridge];
}

- (void)startWithProvider:(NEPacketTunnelProvider *)provider
               packetFlow:(NEPacketTunnelFlow *)packetFlow
            configuration:(NSDictionary<NSString *,id> *)configuration
               completion:(void (^)(NSError * _Nullable))completion {
    self.provider = provider;
    self.packetFlow = packetFlow;
    self.configuration = configuration;
    self.username = [self stringValue:configuration[@"username"]];
    self.password = [self stringValue:configuration[@"password"]];
    self.allowUntrustedServerCertificate = [configuration[@"allowUntrustedServerCertificate"] boolValue];
    self.startCompletion = completion;
    self.startCompleted = NO;
    self.stopping = NO;

    dispatch_async(self.workerQueue, ^{
        [self runOpenConnect];
    });
}

- (void)stopWithCompletion:(void (^)(void))completion {
    self.stopping = YES;
    self.stopCompletion = completion;
    if (self.commandFD >= 0) {
        (void)write(self.commandFD, &XDOpenConnectCancelCommand, 1);
    }
    [self closePacketBridge];
    if (!self.vpninfo) {
        [self finishStopIfNeeded];
    }
}

- (void)runOpenConnect {
    NSError *loadError = nil;
    if (![self loadOpenConnect:&loadError]) {
        [self finishStartWithError:loadError];
        return;
    }

    self.symbols.init_ssl();

    const char *userAgent = "XDVPN iOS";
    self.vpninfo = self.symbols.vpninfo_new(
        userAgent,
        XDValidatePeerCert,
        XDWriteNewConfig,
        XDProcessAuthForm,
        XDProgress,
        (__bridge void *)self
    );
    if (!self.vpninfo) {
        [self finishStartWithError:[self errorWithCode:2 message:@"OpenConnect 初始化失败"]];
        return;
    }

    self.symbols.set_loglevel(self.vpninfo, PRG_DEBUG);
    self.symbols.set_protect_socket_handler(self.vpninfo, XDProtectSocket);
    self.symbols.set_setup_tun_handler(self.vpninfo, XDSetupTun);
    self.symbols.set_stats_handler(self.vpninfo, XDStats);
    if (self.symbols.set_reported_os) {
        self.symbols.set_reported_os(self.vpninfo, "apple-ios");
    }
    if (self.symbols.set_mobile_info) {
        NSString *udid = [NSUUID UUID].UUIDString;
        self.symbols.set_mobile_info(self.vpninfo, "iOS", "iPhone", udid.UTF8String);
    }

    NSString *protocolName = [self stringValue:self.configuration[@"protocol"]];
    if (protocolName.length > 0 && self.symbols.set_protocol(self.vpninfo, protocolName.UTF8String) != 0) {
        [self finishStartWithError:[self errorWithCode:3 message:@"OpenConnect 协议不支持"]];
        [self releaseVPNInfo];
        return;
    }

    NSString *url = [self normalizedURLFromServer:[self stringValue:self.configuration[@"server"]]];
    if (self.symbols.parse_url(self.vpninfo, url.UTF8String) != 0) {
        [self finishStartWithError:[self errorWithCode:4 message:@"服务器地址格式无效"]];
        [self releaseVPNInfo];
        return;
    }

    self.commandFD = self.symbols.setup_cmd_pipe(self.vpninfo);
    if (self.commandFD < 0) {
        [self finishStartWithError:[self errorWithCode:5 message:@"OpenConnect 控制管道创建失败"]];
        [self releaseVPNInfo];
        return;
    }

    int cookieResult = self.symbols.obtain_cookie(self.vpninfo);
    if (cookieResult != 0) {
        [self finishStartWithError:[self errorWithCode:6 message:@"OpenConnect 认证失败，请检查账号、密码或二次验证要求"]];
        [self releaseVPNInfo];
        return;
    }

    int cstpResult = self.symbols.make_cstp_connection(self.vpninfo);
    if (cstpResult != 0) {
        [self finishStartWithError:[self errorWithCode:7 message:@"OpenConnect 建立 TLS 隧道失败"]];
        [self releaseVPNInfo];
        return;
    }

    if (self.symbols.setup_dtls(self.vpninfo, 60) != 0) {
        NSLog(@"[XDVPN] OpenConnect DTLS setup failed; continuing with TLS tunnel");
    }

    int mainloopResult = self.symbols.mainloop(self.vpninfo, 30, RECONNECT_INTERVAL_MIN);
    if (!self.startCompleted && !self.stopping) {
        NSString *message = [NSString stringWithFormat:@"OpenConnect 主循环提前退出（code %d）", mainloopResult];
        [self finishStartWithError:[self errorWithCode:8 message:message]];
    }

    [self closePacketBridge];
    [self releaseVPNInfo];
    [self finishStopIfNeeded];
}

- (BOOL)loadOpenConnect:(NSError **)error {
    if (self.symbols.handle) { return YES; }

    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    NSBundle *bundle = NSBundle.mainBundle;
    NSArray<NSString *> *frameworkNames = @[
        @"libopenconnect.dylib",
        @"OpenConnect.framework/OpenConnect",
        @"openconnect.framework/openconnect"
    ];
    for (NSString *name in frameworkNames) {
        if (bundle.privateFrameworksPath.length > 0) {
            [candidates addObject:[bundle.privateFrameworksPath stringByAppendingPathComponent:name]];
        }
        [candidates addObject:[[bundle.bundlePath stringByAppendingPathComponent:@"Frameworks"] stringByAppendingPathComponent:name]];
        [candidates addObject:[[bundle.bundlePath stringByAppendingPathComponent:@"../../Frameworks"] stringByAppendingPathComponent:name]];
    }
    [candidates addObjectsFromArray:@[
        @"@rpath/libopenconnect.dylib",
        @"@rpath/OpenConnect.framework/OpenConnect",
        @"libopenconnect.dylib"
    ]];

    void *handle = NULL;
    NSMutableArray<NSString *> *failures = [NSMutableArray array];
    for (NSString *candidate in candidates) {
        handle = dlopen(candidate.UTF8String, RTLD_NOW | RTLD_LOCAL);
        if (handle) { break; }
        const char *dlMessage = dlerror();
        if (dlMessage) {
            [failures addObject:[NSString stringWithFormat:@"%@: %s", candidate, dlMessage]];
        }
    }

    if (!handle) {
        NSString *message = @"缺少 iOS libopenconnect。请把 libopenconnect.dylib 或 OpenConnect.framework 嵌入 PacketTunnel/宿主 App 的 Frameworks 后重试。";
        if (failures.count > 0) {
            message = [message stringByAppendingFormat:@"\n%@", [failures componentsJoinedByString:@"\n"]];
        }
        if (error) { *error = [self errorWithCode:1 message:message]; }
        return NO;
    }

    XDOpenConnectSymbols symbols = {0};
    symbols.handle = handle;
    if (![self loadSymbol:@"openconnect_init_ssl" handle:handle target:(void **)&symbols.init_ssl error:error] ||
        ![self loadSymbol:@"openconnect_vpninfo_new" handle:handle target:(void **)&symbols.vpninfo_new error:error] ||
        ![self loadSymbol:@"openconnect_vpninfo_free" handle:handle target:(void **)&symbols.vpninfo_free error:error] ||
        ![self loadSymbol:@"openconnect_set_protocol" handle:handle target:(void **)&symbols.set_protocol error:error] ||
        ![self loadSymbol:@"openconnect_parse_url" handle:handle target:(void **)&symbols.parse_url error:error] ||
        ![self loadSymbol:@"openconnect_obtain_cookie" handle:handle target:(void **)&symbols.obtain_cookie error:error] ||
        ![self loadSymbol:@"openconnect_make_cstp_connection" handle:handle target:(void **)&symbols.make_cstp_connection error:error] ||
        ![self loadSymbol:@"openconnect_setup_dtls" handle:handle target:(void **)&symbols.setup_dtls error:error] ||
        ![self loadSymbol:@"openconnect_setup_cmd_pipe" handle:handle target:(void **)&symbols.setup_cmd_pipe error:error] ||
        ![self loadSymbol:@"openconnect_setup_tun_fd" handle:handle target:(void **)&symbols.setup_tun_fd error:error] ||
        ![self loadSymbol:@"openconnect_mainloop" handle:handle target:(void **)&symbols.mainloop error:error] ||
        ![self loadSymbol:@"openconnect_get_ip_info" handle:handle target:(void **)&symbols.get_ip_info error:error] ||
        ![self loadSymbol:@"openconnect_set_option_value" handle:handle target:(void **)&symbols.set_option_value error:error] ||
        ![self loadSymbol:@"openconnect_set_protect_socket_handler" handle:handle target:(void **)&symbols.set_protect_socket_handler error:error] ||
        ![self loadSymbol:@"openconnect_set_setup_tun_handler" handle:handle target:(void **)&symbols.set_setup_tun_handler error:error] ||
        ![self loadSymbol:@"openconnect_set_stats_handler" handle:handle target:(void **)&symbols.set_stats_handler error:error] ||
        ![self loadSymbol:@"openconnect_set_loglevel" handle:handle target:(void **)&symbols.set_loglevel error:error]) {
        dlclose(handle);
        return NO;
    }

    symbols.set_reported_os = dlsym(handle, "openconnect_set_reported_os");
    symbols.set_mobile_info = dlsym(handle, "openconnect_set_mobile_info");
    symbols.disable_ipv6 = dlsym(handle, "openconnect_disable_ipv6");
    self.symbols = symbols;
    return YES;
}

- (BOOL)loadSymbol:(const char *)name handle:(void *)handle target:(void **)target error:(NSError **)error {
    *target = dlsym(handle, name);
    if (*target) { return YES; }
    NSString *message = [NSString stringWithFormat:@"libopenconnect 缺少符号 %s", name];
    if (error) { *error = [self errorWithCode:9 message:message]; }
    return NO;
}

- (void)configureTunnelFromOpenConnect {
    if (!self.vpninfo || !self.symbols.get_ip_info) { return; }

    int fds[2] = {-1, -1};
    if (socketpair(AF_UNIX, SOCK_DGRAM, 0, fds) != 0) {
        [self finishStartWithError:[self errorWithCode:10 message:@"PacketTunnel socketpair 创建失败"]];
        return;
    }
    self.openconnectFD = fds[0];
    self.packetFlowFD = fds[1];
    [self setNonBlocking:self.packetFlowFD];

    if (self.symbols.setup_tun_fd(self.vpninfo, self.openconnectFD) != 0) {
        [self closePacketBridge];
        [self finishStartWithError:[self errorWithCode:11 message:@"OpenConnect tun fd 接入失败"]];
        return;
    }

    const struct oc_ip_info *ipInfo = NULL;
    const struct oc_vpn_option *cstpOptions = NULL;
    const struct oc_vpn_option *dtlsOptions = NULL;
    self.symbols.get_ip_info(self.vpninfo, &ipInfo, &cstpOptions, &dtlsOptions);

    NEPacketTunnelNetworkSettings *settings = [self makeNetworkSettingsWithIPInfo:ipInfo];
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSError *settingsError = nil;
    [self.provider setTunnelNetworkSettings:settings completionHandler:^(NSError * _Nullable error) {
        settingsError = error;
        dispatch_semaphore_signal(semaphore);
    }];
    long waitResult = dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC));
    if (waitResult != 0) {
        [self finishStartWithError:[self errorWithCode:12 message:@"应用 VPN 网络设置超时"]];
        return;
    }
    if (settingsError) {
        [self finishStartWithError:settingsError];
        return;
    }

    [self startPacketFlowReadLoop];
    [self startPacketFDReadLoop];
    [self finishStartWithError:nil];
}

- (NEPacketTunnelNetworkSettings *)makeNetworkSettingsWithIPInfo:(const struct oc_ip_info *)ipInfo {
    NSString *server = [self stringValue:self.configuration[@"server"]];
    NEPacketTunnelNetworkSettings *settings = [[NEPacketTunnelNetworkSettings alloc] initWithTunnelRemoteAddress:server.length ? server : @"openconnect"];
    settings.MTU = @([self mtuFromIPInfo:ipInfo]);

    NSString *address = [self stringFromCString:ipInfo ? ipInfo->addr : NULL fallback:@"198.18.0.2"];
    NSString *netmask = [self stringFromCString:ipInfo ? ipInfo->netmask : NULL fallback:@"255.255.255.255"];
    NEIPv4Settings *ipv4 = [[NEIPv4Settings alloc] initWithAddresses:@[address] subnetMasks:@[netmask]];
    if ([[self stringValue:self.configuration[@"runningMode"]] isEqualToString:@"split"]) {
        NSArray<NEIPv4Route *> *routes = [self routesFromCIDRs:self.configuration[@"splitCIDRs"]];
        ipv4.includedRoutes = routes.count > 0 ? routes : [self routesFromOpenConnectSplitIncludes:ipInfo];
    } else {
        ipv4.includedRoutes = @[[NEIPv4Route defaultRoute]];
    }
    settings.IPv4Settings = ipv4;

    NSArray<NSString *> *dnsServers = [self dnsServersFromIPInfo:ipInfo];
    if (dnsServers.count > 0) {
        NEDNSSettings *dns = [[NEDNSSettings alloc] initWithServers:dnsServers];
        NSArray<NSString *> *domains = [self stringArray:self.configuration[@"splitDomains"]];
        if ([[self stringValue:self.configuration[@"runningMode"]] isEqualToString:@"split"]) {
            dns.matchDomains = domains.count > 0 ? domains : @[];
        } else {
            dns.matchDomains = @[@""];
        }
        settings.DNSSettings = dns;
    }

    return settings;
}

- (NSInteger)mtuFromIPInfo:(const struct oc_ip_info *)ipInfo {
    if (ipInfo && ipInfo->mtu > 0) { return ipInfo->mtu; }
    return 1280;
}

- (NSArray<NSString *> *)dnsServersFromIPInfo:(const struct oc_ip_info *)ipInfo {
    NSMutableArray<NSString *> *servers = [NSMutableArray array];
    if (!ipInfo) { return servers; }
    for (int i = 0; i < 3; i++) {
        NSString *server = [self stringFromCString:ipInfo->dns[i] fallback:nil];
        if (server.length > 0) { [servers addObject:server]; }
    }
    return servers;
}

- (NSArray<NEIPv4Route *> *)routesFromOpenConnectSplitIncludes:(const struct oc_ip_info *)ipInfo {
    NSMutableArray<NEIPv4Route *> *routes = [NSMutableArray array];
    if (!ipInfo) { return routes; }
    for (struct oc_split_include *include = ipInfo->split_includes; include; include = include->next) {
        NSString *route = [self stringFromCString:include->route fallback:nil];
        NEIPv4Route *parsed = [self routeFromCIDR:route];
        if (parsed) { [routes addObject:parsed]; }
    }
    return routes;
}

- (NSArray<NEIPv4Route *> *)routesFromCIDRs:(id)value {
    NSMutableArray<NEIPv4Route *> *routes = [NSMutableArray array];
    for (NSString *cidr in [self stringArray:value]) {
        NEIPv4Route *route = [self routeFromCIDR:cidr];
        if (route) { [routes addObject:route]; }
    }
    return routes;
}

- (NEIPv4Route *)routeFromCIDR:(NSString *)cidr {
    if (cidr.length == 0) { return nil; }
    NSArray<NSString *> *parts = [cidr componentsSeparatedByString:@"/"];
    if (parts.count != 2) { return nil; }
    NSInteger prefix = parts[1].integerValue;
    if (prefix < 0 || prefix > 32) { return nil; }
    NSString *mask = [self subnetMaskForPrefix:prefix];
    if (!mask) { return nil; }
    return [[NEIPv4Route alloc] initWithDestinationAddress:parts[0] subnetMask:mask];
}

- (NSString *)subnetMaskForPrefix:(NSInteger)prefix {
    if (prefix < 0 || prefix > 32) { return nil; }
    uint32_t mask = prefix == 0 ? 0 : htonl(UINT32_MAX << (32 - prefix));
    struct in_addr addr;
    addr.s_addr = mask;
    char buffer[INET_ADDRSTRLEN] = {0};
    const char *text = inet_ntop(AF_INET, &addr, buffer, sizeof(buffer));
    return text ? [NSString stringWithUTF8String:text] : nil;
}

- (void)startPacketFlowReadLoop {
    if (self.packetFlowFD < 0) { return; }
    __weak typeof(self) weakSelf = self;
    [self.packetFlow readPacketsWithCompletionHandler:^(NSArray<NSData *> *packets, NSArray<NSNumber *> *protocols) {
        __strong typeof(self) self = weakSelf;
        if (!self || self.packetFlowFD < 0 || self.stopping) { return; }
        for (NSUInteger i = 0; i < packets.count; i++) {
            sa_family_t family = protocols[i].intValue;
            NSData *packet = packets[i];
            [self writePacketToOpenConnect:packet family:family];
        }
        [self startPacketFlowReadLoop];
    }];
}

- (void)writePacketToOpenConnect:(NSData *)packet family:(sa_family_t)family {
    if (self.packetFlowFD < 0 || packet.length == 0) { return; }
    uint32_t prefix = htonl((uint32_t)family);
    NSMutableData *framed = [NSMutableData dataWithBytes:&prefix length:sizeof(prefix)];
    [framed appendData:packet];
    ssize_t written = write(self.packetFlowFD, framed.bytes, framed.length);
    if (written < 0 && errno != EAGAIN && errno != EWOULDBLOCK) {
        NSLog(@"[XDVPN] write packet to OpenConnect failed: %s", strerror(errno));
    }
}

- (void)startPacketFDReadLoop {
    if (self.packetFlowFD < 0) { return; }
    int fd = self.packetFlowFD;
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)fd, 0, self.packetQueue);
    self.packetReadSource = source;
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(source, ^{
        __strong typeof(self) self = weakSelf;
        if (!self) { return; }
        [self drainPacketsFromOpenConnect];
    });
    dispatch_source_set_cancel_handler(source, ^{
        close(fd);
    });
    dispatch_resume(source);
}

- (void)drainPacketsFromOpenConnect {
    if (self.packetFlowFD < 0) { return; }
    uint8_t buffer[65536];
    while (true) {
        ssize_t length = read(self.packetFlowFD, buffer, sizeof(buffer));
        if (length < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK) { return; }
            NSLog(@"[XDVPN] read packet from OpenConnect failed: %s", strerror(errno));
            return;
        }
        if (length == 0) { return; }
        if (length <= (ssize_t)sizeof(uint32_t)) { continue; }
        uint32_t family = 0;
        memcpy(&family, buffer, sizeof(family));
        family = ntohl(family);
        NSData *packet = [NSData dataWithBytes:buffer + sizeof(uint32_t) length:(NSUInteger)length - sizeof(uint32_t)];
        [self.packetFlow writePackets:@[packet] withProtocols:@[@(family)]];
    }
}

- (void)closePacketBridge {
    if (self.packetReadSource) {
        dispatch_source_cancel(self.packetReadSource);
        self.packetReadSource = nil;
        self.packetFlowFD = -1;
    } else if (self.packetFlowFD >= 0) {
        close(self.packetFlowFD);
        self.packetFlowFD = -1;
    }
    if (self.openconnectFD >= 0) {
        close(self.openconnectFD);
        self.openconnectFD = -1;
    }
}

- (void)releaseVPNInfo {
    if (self.vpninfo && self.symbols.vpninfo_free) {
        self.symbols.vpninfo_free(self.vpninfo);
    }
    self.vpninfo = NULL;
    self.commandFD = -1;
}

- (void)finishStartWithError:(NSError *)error {
    void (^completion)(NSError *) = self.startCompletion;
    if (!completion || self.startCompleted) { return; }
    self.startCompleted = YES;
    self.startCompletion = nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(error);
    });
}

- (void)finishStopIfNeeded {
    void (^completion)(void) = self.stopCompletion;
    if (!completion) { return; }
    self.stopCompletion = nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        completion();
    });
}

- (void)setNonBlocking:(int)fd {
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags >= 0) {
        fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    }
}

- (NSError *)errorWithCode:(NSInteger)code message:(NSString *)message {
    return [NSError errorWithDomain:XDOpenConnectErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"OpenConnect failed"}];
}

- (NSString *)normalizedURLFromServer:(NSString *)server {
    if (server.length == 0) { return @""; }
    if ([server containsString:@"://"]) { return server; }
    return [@"https://" stringByAppendingString:server];
}

- (NSString *)stringValue:(id)value {
    if ([value isKindOfClass:NSString.class]) { return value; }
    if ([value respondsToSelector:@selector(stringValue)]) { return [value stringValue]; }
    return @"";
}

- (NSArray<NSString *> *)stringArray:(id)value {
    if (![value isKindOfClass:NSArray.class]) { return @[]; }
    NSMutableArray<NSString *> *strings = [NSMutableArray array];
    for (id item in (NSArray *)value) {
        NSString *text = [self stringValue:item];
        if (text.length > 0) { [strings addObject:text]; }
    }
    return strings;
}

- (NSString *)stringFromCString:(const char *)value fallback:(NSString *)fallback {
    if (!value || value[0] == '\0') { return fallback; }
    return [NSString stringWithUTF8String:value] ?: fallback;
}

static XDOpenConnectRuntime *XDContext(void *privdata) {
    return (__bridge XDOpenConnectRuntime *)privdata;
}

static int XDValidatePeerCert(void *privdata, const char *reason) {
    XDOpenConnectRuntime *runtime = XDContext(privdata);
    NSString *message = reason ? [NSString stringWithUTF8String:reason] : @"unknown certificate error";
    if (runtime.allowUntrustedServerCertificate) {
        NSLog(@"[XDVPN] accepting OpenConnect peer certificate because allowUntrustedServerCertificate is enabled: %@", message);
        return 0;
    }

    NSLog(@"[XDVPN] rejecting OpenConnect peer certificate: %@", message);
    return -1;
}

static int XDWriteNewConfig(void *privdata, const char *buf, int buflen) {
    (void)privdata;
    (void)buf;
    (void)buflen;
    return 0;
}

static int XDProcessAuthForm(void *privdata, struct oc_auth_form *form) {
    XDOpenConnectRuntime *runtime = XDContext(privdata);
    if (!runtime) { return -1; }

    BOOL wroteUsername = NO;
    BOOL wrotePassword = NO;
    for (struct oc_form_opt *opt = form ? form->opts : NULL; opt; opt = opt->next) {
        NSString *name = opt->name ? [NSString stringWithUTF8String:opt->name].lowercaseString : @"";
        NSString *label = opt->label ? [NSString stringWithUTF8String:opt->label].lowercaseString : @"";
        BOOL wantsUsername = opt->type == OC_FORM_OPT_TEXT &&
            ([name containsString:@"user"] || [label containsString:@"user"] || [label containsString:@"用户名"]);
        BOOL wantsPassword = opt->type == OC_FORM_OPT_PASSWORD ||
            [name containsString:@"pass"] || [label containsString:@"pass"] || [label containsString:@"密码"];

        if (wantsUsername && runtime.username.length > 0) {
            runtime.symbols.set_option_value(opt, runtime.username.UTF8String);
            wroteUsername = YES;
        } else if (wantsPassword && runtime.password.length > 0) {
            runtime.symbols.set_option_value(opt, runtime.password.UTF8String);
            wrotePassword = YES;
        }
    }

    if (!wroteUsername || !wrotePassword) {
        NSLog(@"[XDVPN] auth form did not consume all supplied credentials user=%d password=%d", wroteUsername, wrotePassword);
    }
    return 0;
}

static void XDProgress(void *privdata, int level, const char *fmt, ...) {
    if (level > PRG_DEBUG || !fmt) { return; }
    va_list args;
    va_start(args, fmt);
    NSString *format = [NSString stringWithUTF8String:fmt] ?: @"";
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"[XDVPN] OpenConnect %@", [message stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]);
    (void)privdata;
}

static void XDProtectSocket(void *privdata, int fd) {
    (void)privdata;
    (void)fd;
}

static void XDSetupTun(void *privdata) {
    XDOpenConnectRuntime *runtime = XDContext(privdata);
    [runtime configureTunnelFromOpenConnect];
}

static void XDStats(void *privdata, const struct oc_stats *stats) {
    (void)privdata;
    (void)stats;
}

@end
