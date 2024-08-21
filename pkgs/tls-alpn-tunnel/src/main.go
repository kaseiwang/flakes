package main

import (
	"flag"
	"fmt"
	"io"
	"net"
	"os"
	"os/signal"
	"syscall"

	utls "github.com/refraction-networking/utls"
)

var (
	localAddr  = flag.String("localAddr", "127.0.0.1", "local address to listen on.")
	localPort  = flag.String("localPort", "1984", "local port to listen on.")
	remoteAddr = flag.String("remoteAddr", "127.0.0.1", "remote address to forward.")
	remotePort = flag.String("remotePort", "1080", "remote port to forward.")
	host       = flag.String("host", "", "Hostname for server.")
	alpn       = flag.String("alpn", "smtp", "alpn protocol")
)

func forwardloop(src, dst net.Conn, name string) {
	n, err := io.Copy(src, dst)
	dsterr := dst.Close()

	e1 := "noerr"
	e2 := "noerr"
	if err != nil {
		e1 = err.Error()
	}
	if dsterr != nil {
		e2 = dsterr.Error()
	}

	fmt.Printf("%s conn closed, readed %d, src %s, dst %s\n", name, n, e1, e2)
}

func GetHelloSpec(alpn []string) *utls.ClientHelloSpec {
	return &utls.ClientHelloSpec{
		CipherSuites: []uint16{
			utls.GREASE_PLACEHOLDER,
			utls.TLS_AES_128_GCM_SHA256,
			utls.TLS_AES_256_GCM_SHA384,
			utls.TLS_CHACHA20_POLY1305_SHA256,
			utls.TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,
			utls.TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
			utls.TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,
			utls.TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
			utls.TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305,
			utls.TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305,
			utls.TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA,
			utls.TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA,
			utls.TLS_RSA_WITH_AES_128_GCM_SHA256,
			utls.TLS_RSA_WITH_AES_256_GCM_SHA384,
			utls.TLS_RSA_WITH_AES_128_CBC_SHA,
			utls.TLS_RSA_WITH_AES_256_CBC_SHA,
		},
		CompressionMethods: []byte{
			0x00, // compressionNone
		},
		Extensions: []utls.TLSExtension{
			&utls.UtlsGREASEExtension{},
			&utls.SNIExtension{},
			&utls.UtlsExtendedMasterSecretExtension{},
			&utls.RenegotiationInfoExtension{Renegotiation: utls.RenegotiateOnceAsClient},
			&utls.SupportedCurvesExtension{[]utls.CurveID{
				utls.GREASE_PLACEHOLDER,
				utls.X25519,
				utls.CurveP256,
				utls.CurveP384,
			}},
			&utls.SupportedPointsExtension{SupportedPoints: []byte{
				0x00, // pointFormatUncompressed
			}},
			&utls.SessionTicketExtension{},
			&utls.ALPNExtension{AlpnProtocols: alpn},
			&utls.StatusRequestExtension{},
			&utls.SignatureAlgorithmsExtension{SupportedSignatureAlgorithms: []utls.SignatureScheme{
				utls.ECDSAWithP256AndSHA256,
				utls.PSSWithSHA256,
				utls.PKCS1WithSHA256,
				utls.ECDSAWithP384AndSHA384,
				utls.PSSWithSHA384,
				utls.PKCS1WithSHA384,
				utls.PSSWithSHA512,
				utls.PKCS1WithSHA512,
			}},
			&utls.SCTExtension{},
			&utls.KeyShareExtension{[]utls.KeyShare{
				{Group: utls.CurveID(utls.GREASE_PLACEHOLDER), Data: []byte{0}},
				{Group: utls.X25519},
			}},
			&utls.PSKKeyExchangeModesExtension{[]uint8{
				utls.PskModeDHE,
			}},
			&utls.SupportedVersionsExtension{[]uint16{
				utls.GREASE_PLACEHOLDER,
				utls.VersionTLS13,
				utls.VersionTLS12,
			}},
			&utls.UtlsCompressCertExtension{[]utls.CertCompressionAlgo{
				utls.CertCompressionBrotli,
			}},
			&utls.ApplicationSettingsExtension{SupportedProtocols: []string{"h2"}},
			&utls.UtlsGREASEExtension{},
			&utls.UtlsPaddingExtension{GetPaddingLen: utls.BoringPaddingStyle},
		},
	}
}

func workloop(conn net.Conn) {
	serverconn, err := net.Dial("tcp", *remoteAddr+":"+*remotePort)
	if serverconn == nil {
		fmt.Println("Connect remote server failed", err)
		return
	}
	fmt.Println("connected to remote", serverconn)

	utlsconfig := &utls.Config{
		NextProtos:         []string{*alpn},
		ServerName:         *host,
		InsecureSkipVerify: false,
	}

	utlsconn := utls.UClient(serverconn, utlsconfig, utls.HelloCustom)
	spec := GetHelloSpec([]string{*alpn})
	utlsconn.SetSNI(*host)
	utlsconn.ApplyPreset(spec)

	if utlsconn == nil {
		serverconn.Close()
		fmt.Println("TLS handshake failed")
	}

	err = utlsconn.Handshake()
	if err != nil {
		fmt.Println("TLS handshake failed")
		os.Exit(-1)
	}

	go forwardloop(utlsconn, conn, "uplink")
	go forwardloop(conn, utlsconn, "downlink")
}

func runServer() {
	listener, err := net.Listen("tcp", *localAddr+":"+*localPort)
	if err != nil {
		panic(err)
	}
	defer listener.Close()

	for {
		conn, err := listener.Accept()
		if conn == nil {
			fmt.Println("Accpet failed on ", conn, err)
			continue
		} else {
			fmt.Println("new conn", conn)
		}
		go workloop(conn)
	}
}

func main() {
	flag.Parse()

	go runServer()

	defer func() {
		fmt.Println("Quiting")
	}()

	osSignals := make(chan os.Signal, 1)
	signal.Notify(osSignals, os.Interrupt, syscall.SIGTERM)
	<-osSignals
}
