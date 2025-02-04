package process

import (
	"context"
	"net/netip"

	"github.com/sagernet/sing-tun"
	E "github.com/sagernet/sing/common/exceptions"

	"github.com/shirou/gopsutil/v4/net"
	"github.com/shirou/gopsutil/v4/process"
)

var _ Searcher = (*androidSearcher)(nil)

type androidSearcher struct {
	packageManager tun.PackageManager
}

func NewSearcher(config Config) (Searcher, error) {
	return &androidSearcher{config.PackageManager}, nil
}

func (s *androidSearcher) FindProcessInfo(ctx context.Context, network string, source netip.AddrPort, destination netip.AddrPort) (*Info, error) {
	// inode, uid, err := resolveSocketByNetlink(network, source, destination) 9e933a215cf327869a6be8f47f09ae611329c499
	uid, err := resolveSocketUID(source.Addr(), source.Port())
	if err != nil {
		return nil, err
	}
	// if processPath, _ := resolveProcessNameByProcSearch(inode, uid); processPath != "" {
	// 	info := Info{
	// 		UserId: int32(uid),
	// 	}
	// 	if _, loaded := s.packageManager.IDByPackage(processPath); loaded {
	// 		info.PackageName = processPath
	// 	} else {
	// 		info.ProcessPath = processPath
	// 	}
	// 	return &info, nil
	// } 9e933a215cf327869a6be8f47f09ae611329c499
	if sharedPackage, loaded := s.packageManager.SharedPackageByID(uid % 100000); loaded {
		return &Info{
			UserId:      int32(uid),
			PackageName: sharedPackage,
		}, nil
	}
	if packageName, loaded := s.packageManager.PackageByID(uid % 100000); loaded {
		return &Info{
			UserId:      int32(uid),
			PackageName: packageName,
		}, nil
	}

	name, path, err := resolveProcessNamePathByUID(uid)
	if err != nil {
		return nil, err
	}
	info := Info{
		UserId: int32(uid),
	}
	if name != "" {
		info.PackageName = name
	}
	if path != "" {
		info.ProcessPath = path
	}
	return &info, nil
}

func resolveSocketUID(srcIP netip.Addr, srcPort uint16) (uint32, error) {
	connections, err := net.Connections("all")
	if err != nil {
		return 0, err
	}

	for _, conn := range connections {
		if conn.Laddr.Port == uint32(srcPort) && conn.Laddr.IP == srcIP.String() {
			if len(conn.Uids) > 0 {
				return uint32(conn.Uids[0]), nil
			}
		}
	}
	return 0, ErrNotFound
}

func resolveProcessNamePathByUID(uid uint32) (string, string, error) {
	processes, err := process.Processes()
	if err != nil {
		return "", "", err
	}

	for _, p := range processes {
		puid, err := p.Uids()
		if err == nil && len(puid) > 0 && uint32(puid[0]) == uid {
			name, err1 := p.Name()
			path, err2 := p.Exe()
			if err1 != nil || err2 != nil {
				continue
			}
			return name, path, nil
		}
	}
	return "", "", E.New("process of uid not found", uid)
}
