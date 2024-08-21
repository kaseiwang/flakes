#!/usr/bin/env python3

import socket
import asyncio
import requests
import yaml
import argparse
import json
import logging
import sys
import time
from pyroute2 import IPRoute, NDB

class Config():
    def __init__(self, filename):
        with open(filename, 'r') as f:
            config = yaml.safe_load(f)
            self.interface = config.get('interface', '')
            self.apiurl = config.get('apiurl', '')
            self.apikey = config.get('apikey', '')
            self.proxy = config.get('proxy', None)

class DDNS():
    def __init__(self, configfile):
        self.ipr = IPRoute()
        self.messages = []
        self.ipr.bind()
        self.config = Config(configfile)
        self.logger = logging.getLogger('ddns')
        handler = logging.StreamHandler(sys.stdout)
        formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
        handler.setFormatter(formatter)
        self.logger.addHandler(handler)
        self.logger.setLevel(logging.INFO)

    def GetInterfaceIP(self):
        ipaddrs = []
        with NDB() as ndb:
            with ndb.interfaces[self.config.interface] as iface:
                ipdump = iface.ipaddr.dump()
                ipdump.select_records(family=socket.AF_INET6)
                for record in ipdump:
                    ipaddr = record._as_dict().get('address')
                    if ipaddr and not ipaddr.startswith('fe80'):
                        ipaddrs.append(ipaddr)
        return ipaddrs

    def GetRecordIP(self):
        headers = {"Authorization": "Bearer " + self.config.apikey}
        proxies = { 'http': self.config.proxy, "https":  self.config.proxy }
        while True:
            try:
                resp = requests.get(self.config.apiurl, headers = headers, proxies = proxies).json()
                if resp['success'] == False:
                    return None
                return resp.get('result', {}).get('content', None)
            except Exception as e:
                self.logger.info(e, exc_info=True)
            time.sleep(1)
        return None

    def UpdateRecordIP(self, ipaddr):
        while True:
            headers = {"Authorization": "Bearer " + self.config.apikey, "Content-Type": "application/json"}
            payload = {"type":"AAAA","name":"cmcc.i.kasei.im","content":ipaddr,"ttl":60,"proxied":False}
            proxies = { 'http': self.config.proxy, "https":  self.config.proxy}
            try:
                resp = requests.put(self.config.apiurl, headers = headers, proxies = proxies, data = json.dumps(payload)).json()
                if resp['success'] == True:
                    self.logger.info("Update record ip success")
                    return True
                else:
                    self.logger.info(resp)
            except Exception as e:
                time.sleep(1)
                self.logger.info(e, exc_info=True)
                self.logger.info("update record ip failed, retry")
                continue

    def Run(self):
        self.logger.info("run on:" + self.config.interface)
        previpaddr = self.GetRecordIP()
        if previpaddr:
            self.logger.info("Record IP: " + previpaddr)
        while True:
            try:
                ipaddrs = self.GetInterfaceIP()
                if len(ipaddrs) > 0:
                    curripaddr = ipaddrs[0]
                    if curripaddr != previpaddr:
                        self.logger.info("New IP: " + curripaddr)
                        self.UpdateRecordIP(curripaddr)
                        previpaddr = curripaddr
            except Exception as e:
                self.logger.info(e, exc_info=True)
            time.sleep(15)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(prog='ddns')
    parser.add_argument('-c', dest='config')
    args = parser.parse_args()
    DDNS(args.config).Run()