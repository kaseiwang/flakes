#include <errno.h>
#include <stdint.h>

#include <linux/string.h>
#include <linux/udp.h>
#include <linux/bpf.h>

#include <linux/if_ether.h>
#include <linux/in.h>
#include <linux/ip.h>
#include <linux/ipv6.h>
#include <linux/pkt_cls.h>

#include <bpf/bpf_helpers.h>
#include <bpf/bpf_endian.h>

/* wireguard message header */
struct message_header {
    __u8    type;
    __u8    client_id[3]; /* was reserved_zero */
};

struct v6_addr_wide {
    __u64 d1;
    __u64 d2;
};

struct wgcf_config_s {
    struct in_addr  peer_addr_v4;
    struct in6_addr peer_addr_v6;
    __u16   peer_port;
    __u8    client_id[3];
};

struct {
    __uint(type, BPF_MAP_TYPE_PERCPU_ARRAY);
    __type(key, __u32);
    __type(value, struct wgcf_config_s);
    __uint(pinning, LIBBPF_PIN_BY_NAME);
    __uint(max_entries, 1);
} wgcf_config_map SEC(".maps");

struct wgcf_config_s config_g = {
    .peer_addr_v4 = { 0x01c09fa2 }, // 162.159.192.1, network order
    //.peer_addr_v4 = { 0x06c19fa2 }, // 162.159.193.6, network order
    .peer_addr_v6 = {},
    .peer_port = 2408,
    .client_id = {0xd3, 0xe3, 0x35},
};

#ifndef likely
# define likely(X)		__builtin_expect(!!(X), 1)
#endif

#ifndef unlikely
# define unlikely(X)		__builtin_expect(!!(X), 0)
#endif

#if !defined(__section)
#define __section(NAME)  __attribute__((section(NAME), used))
#endif

#define bool	_Bool

static __always_inline bool
ctx_no_room(const void *needed, const void *limit)
{
    return unlikely(needed > limit);
}

static __always_inline bool
ipv6_addr_equal(const struct in6_addr *_a1, const struct in6_addr *_a2)
{
    const struct v6_addr_wide *a1 = (const struct v6_addr_wide *)_a1;
    const struct v6_addr_wide *a2 = (const struct v6_addr_wide *)_a2;
    return a1->d1 == a2->d1 && a1->d2 == a2->d2;
}

static __always_inline struct wgcf_config_s*
get_config()
{
    struct wgcf_config_s* config;
    int index = 0;

    return &config_g;
    return bpf_map_lookup_elem(&wgcf_config_map, &index);
}

/* ret: 1 for modified, 0 for untouched, negative for error
 */
long
wg_cf_process(void* data, void* data_end, bool direction)
{
    struct ethhdr           *eth = data;
    struct udphdr           *udph = NULL;
    struct message_header   *wgh = NULL;
    struct wgcf_config_s    *config = get_config();

    if (unlikely(config == NULL)) {
        return 0;
    }

    if (ctx_no_room(eth + 1, data_end)) {
        return 0;
    }

    if (eth->h_proto == bpf_htons(ETH_P_IP)) {
        data += sizeof(struct ethhdr);
        struct iphdr *iph = data;
        if (ctx_no_room(iph + 1, data_end)) {
            return 0;
        }

        if ((direction == 1 && iph->daddr != config->peer_addr_v4.s_addr) // egress
          || (direction == 0 && iph->saddr != config->peer_addr_v4.s_addr)) // ingress
        {
            return 0;
        }

        data += sizeof(struct iphdr);
        udph = data;
        if (ctx_no_room(udph + 1, data_end)) {
            return 0;
        }
    } else if (eth->h_proto == bpf_htons(ETH_P_IPV6)) {
        data += sizeof(struct ethhdr);
        struct ipv6hdr *ip6h = data;
        if (ctx_no_room(ip6h + 1, data_end)) {
            return 0;
        }

        if ((direction == 1 && !ipv6_addr_equal(&ip6h->daddr, &config->peer_addr_v6)) // egress
          ||(direction == 0 && !ipv6_addr_equal(&ip6h->saddr, &config->peer_addr_v6))) // ingress
        {
            return 0;
        }

        data += sizeof(struct ipv6hdr);
        udph = data;
        if (ctx_no_room(udph + 1, data_end)) {
            return 0;
        }
    } else {
        return 0;
    }

    /* egress */
    if (udph && direction == 1
        && udph->dest == bpf_htons(config->peer_port))
    {
        data += sizeof(struct udphdr);
        wgh = data;
        if (ctx_no_room(wgh + 1, data_end)) {
            return 0;
        }

        //wgh->type |= 0xc0;
        wgh->client_id[0] = config->client_id[0];
        wgh->client_id[1] = config->client_id[1];
        wgh->client_id[2] = config->client_id[2];

        return 1;
    /* ingress */
    } else if (udph && direction == 0
               && udph->source == bpf_htons(config->peer_port))
    {
        data += sizeof(struct udphdr);
        wgh = data;
        if (ctx_no_room(wgh + 1, data_end)) {
            return 0;
        }

        //wgh->type &= 0x0f;
        wgh->client_id[0] = 0;
        wgh->client_id[1] = 0;
        wgh->client_id[2] = 0;

        /* drop checksum since udp payload is modified.
         * since wireguard has poly1305 auth tag, this is no harm, but might
         * pass some bad packet to wireguard module. */
        udph->check = 0;
        return 1;
    }

    return 0;
}

SEC("wg-cf-xdp-ingress")
int wg_cf_inbound(struct xdp_md *ctx)
{
    void *data_end = (void *) (long) ctx->data_end;
    void *data = (void *) (long) ctx->data;

    (void)wg_cf_process(data, data_end, 0);

    return XDP_PASS;
}

SEC("wg-cf-tc-egress")
int wg_cf_outbound(struct __sk_buff *ctx)
{
    void *data_end = (void *) (long) ctx->data_end;
    void *data = (void *) (long) ctx->data;

    (void)wg_cf_process(data, data_end, 1);

    return TC_ACT_OK;
}

char __license[] __section("license") = "GPL";
