#!/bin/bash

INTERFACE="wanbr"

function addV6Addr() {
    printf "ip -6 addr add $1 dev $INTERFACE\n"
}

function addV6Route() {
    printf "ip -6 route add default via $1 dev $INTERFACE\n"
}

function generateV6Addr() {
    ip_address=$1

    # 提取IP地址和子网掩码
    address=$(echo $ip_address | cut -d '/' -f 1)
    subnet_mask=$(echo $ip_address | cut -d '/' -f 2)

    # 将IP地址分成4个部分
    IFS='.' read -r -a address_parts <<< "$address"

    # 计算子网掩码的位数
    bits=$((32 - subnet_mask))

    # 计算子网掩码
    subnet=$(((0xffffffff << $bits) & 0xffffffff))
    hostmask=$((0xffff))

    # 计算网络地址
    network=$((subnet & (address_parts[0] << 24 | address_parts[1] << 16 | address_parts[2] << 8 | address_parts[3])))

    # 计算主机地址
    host=$((hostmask & (address_parts[0] << 24 | address_parts[1] << 16 | address_parts[2] << 8 | address_parts[3])))

    printf -v V6GateWay "fd00:%d:%d:%d::1\n" $((network >> 24 & 0xff)) $((network >> 16 & 0xff)) $((network >> 8 & 0xff))
    printf -v V6Address "fd00:%d:%d:%d::%d:%d/64\n" $((network >> 24 & 0xff)) $((network >> 16 & 0xff)) $((network >> 8 & 0xff))  $((host >> 8 & 0xff)) $((host & 0xff))

    addV6Addr $V6Address
    addV6Route $V6GateWay
}

function getV4Addr() {
    v4addr=$(ip addr show dev $1 | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}/[0-9]{1,3}" | head -n 1)
    generateV6Addr $v4addr
}

getV4Addr $INTERFACE