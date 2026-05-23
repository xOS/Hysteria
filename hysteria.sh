#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

#=================================================
# 系统要求: Linux (systemd)
# 描述: Hysteria 2 安装与管理脚本
# 作者: 春夏
# 主页: https://aapls.com
#=================================================

sh_ver="0.1.1"
repo_owner="apernet"
repo_name="hysteria"
shell_url="https://raw.githubusercontent.com/xOS/Hysteria/master/hysteria.sh"

script_dir=$(cd "$(dirname "$0")"; pwd)
script_name=$(basename "$0")
install_dir="/etc/hysteria"
bin_dir="/usr/local/bin"
service_name="hysteria-server.service"
service_path="/etc/systemd/system/${service_name}"
config_file="${install_dir}/config.yaml"
cert_file="${install_dir}/server.crt"
key_file="${install_dir}/server.key"
server_bin="${bin_dir}/hysteria"

Green_font_prefix="\033[32m" && Red_font_prefix="\033[31m" && Green_background_prefix="\033[42;37m" && Red_background_prefix="\033[41;37m" && Font_color_suffix="\033[0m" && Yellow_font_prefix="\033[0;33m"
Info="${Green_font_prefix}[信息]${Font_color_suffix}"
Error="${Red_font_prefix}[错误]${Font_color_suffix}"
Tip="${Yellow_font_prefix}[注意]${Font_color_suffix}"

release=""
arch=""
status=""

hy_listen=":8443"
hy_listen_mode="default"
hy_auth_type="password"
hy_password=""
hy_user=""
hy_userpass=""
hy_tls_mode="tls"
hy_acme_domains=""
hy_acme_email=""
hy_cert_path="${cert_file}"
hy_key_path="${key_file}"
hy_obfs_enable="false"
hy_obfs_type="salamander"
hy_obfs_password=""
hy_masquerade_enable="false"
hy_masquerade_type="proxy"
hy_masquerade_url=""
hy_masquerade_rewrite_host="true"
hy_masquerade_insecure="false"
hy_masquerade_x_forwarded="false"
hy_masquerade_dir=""
hy_masquerade_string=""
hy_masquerade_status="200"
hy_client_sni=""
hy_default_sni=""

default_self_signed_cn="www.bing.com"
default_masquerade_url="https://www.bing.com"
default_masquerade_dir="/www/masq"
default_masquerade_string="hello"
default_masquerade_status="200"

sni_candidates=(
	"ads.apple.com"
	"advertising.apple.com"
	"apps.apple.com"
	"asia.apple.com"
	"books.apple.com"
	"community.apple.com"
	"crl.apple.com"
	"developer.apple.com"
	"files.apple.com"
	"guide.apple.com"
	"iphone.apple.com"
	"link.apple.com"
	"maps.apple.com"
	"ml.apple.com"
	"music.apple.com"
	"one.apple.com"
	"store.apple.com"
	"support.apple.com"
	"time.apple.com"
	"tv.apple.com"
	"videos.apple.com"
)

surge_ecn="true"

checkRoot(){
	[[ $EUID != 0 ]] && echo -e "${Error} 当前非ROOT账号(或没有ROOT权限)，无法继续操作，请更换ROOT账号或使用 ${Green_background_prefix}sudo su${Font_color_suffix} 命令获取临时ROOT权限。" && exit 1
}

checkSys(){
	if [[ ! -d /run/systemd/system ]]; then
		echo -e "${Error} 未检测到 systemd，本脚本需要 systemd 环境。"
		exit 1
	fi
	if [[ -f /etc/redhat-release ]]; then
		release="centos"
	elif cat /etc/issue 2>/dev/null | grep -q -E -i "debian"; then
		release="debian"
	elif cat /etc/issue 2>/dev/null | grep -q -E -i "ubuntu"; then
		release="ubuntu"
	elif cat /etc/issue 2>/dev/null | grep -q -E -i "centos|red hat|redhat|rocky|alma|fedora"; then
		release="centos"
	elif cat /proc/version 2>/dev/null | grep -q -E -i "debian"; then
		release="debian"
	elif cat /proc/version 2>/dev/null | grep -q -E -i "ubuntu"; then
		release="ubuntu"
	elif cat /proc/version 2>/dev/null | grep -q -E -i "centos|red hat|redhat|rocky|alma|fedora"; then
		release="centos"
	elif [[ -f /etc/os-release ]]; then
		. /etc/os-release
		case "${ID:-}" in
			ubuntu) release="ubuntu" ;;
			debian) release="debian" ;;
			centos|rhel|rocky|almalinux|fedora) release="centos" ;;
		esac
	fi
	[[ -z "${release}" ]] && echo -e "${Error} 暂不支持当前系统，请使用 Debian/Ubuntu/CentOS/RHEL 系列 Linux。" && exit 1
}

checkDependencies(){
	local deps=("curl" "openssl" "grep" "sed" "awk")
	for cmd in "${deps[@]}"; do
		if ! command -v "$cmd" >/dev/null 2>&1; then
			echo -e "${Error} 缺少依赖: ${cmd}，正在尝试安装..."
			installDependencies
			return 0
		fi
	done
	echo -e "${Info} 依赖检查完成"
}

installDependencies(){
	if [[ ${release} == "centos" ]]; then
		if command -v dnf >/dev/null 2>&1; then
			dnf install -y curl openssl ca-certificates
		else
			yum install -y curl openssl ca-certificates
		fi
	else
		apt-get update
		apt-get install -y curl openssl ca-certificates
	fi
	echo -e "${Info} 依赖安装完成"
}

sysArch(){
	local uname_arch
	uname_arch=$(uname -m)
	if [[ "${uname_arch}" == "x86_64" ]] || [[ "${uname_arch}" == "amd64" ]]; then
		arch="amd64"
	elif [[ "${uname_arch}" == "aarch64" ]] || [[ "${uname_arch}" == "arm64" ]]; then
		arch="arm64"
	else
		echo -e "${Error} 暂不支持当前架构：${uname_arch}"
		exit 1
	fi
}

checkInstalledStatus(){
	[[ ! -e ${server_bin} ]] && echo -e "${Error} Hysteria 服务端未安装，请检查！" && exit 1
}

checkStatus(){
	if systemctl is-active "${service_name}" >/dev/null 2>&1; then
		status="running"
	else
		status="stopped"
	fi
}

generatePassword(){
	tr -dc A-Za-z0-9 </dev/urandom | head -c 16
}

detectPublicHost(){
	local hostaddr
	hostaddr=$(curl -4 -fsS --max-time 5 https://ip.sb 2>/dev/null || true)
	[[ -n "${hostaddr}" ]] && echo "${hostaddr}" && return 0
	hostaddr=$(curl -4 -fsS --max-time 5 https://api.ip.sb/ip 2>/dev/null || true)
	[[ -n "${hostaddr}" ]] && echo "${hostaddr}" && return 0
	hostaddr=$(curl -4 -fsS --max-time 5 https://ifconfig.me 2>/dev/null || true)
	[[ -n "${hostaddr}" ]] && echo "${hostaddr}" && return 0
	hostname -f 2>/dev/null || hostname
}

detectReleaseAsset(){
	sysArch
	if [[ "${arch}" == "amd64" ]]; then
		echo "hysteria-linux-amd64"
	else
		echo "hysteria-linux-arm64"
	fi
}

downloadRelease(){
	local asset_name=$1
	local release_url="https://github.com/${repo_owner}/${repo_name}/releases/latest/download/${asset_name}"
	local tmpdir
	local bin_path

	tmpdir=$(mktemp -d)
	bin_path="${tmpdir}/${asset_name}"

	echo -e "${Info} 正在下载 Hysteria release：${asset_name}"
	if ! curl -fL --connect-timeout 15 --max-time 300 "${release_url}" -o "${bin_path}"; then
		rm -rf "${tmpdir}"
		echo -e "${Error} 下载失败：${release_url}"
		return 1
	fi

	install -m 0755 "${bin_path}" "${server_bin}"
	rm -rf "${tmpdir}"
	echo -e "${Info} Hysteria 主程序下载安装完毕！"
	return 0
}

normalizeVersion(){
	echo "$1" | grep -oE 'v?[0-9]+(\.[0-9]+)+' | head -n 1
}

getLocalVersion(){
	[[ ! -e ${server_bin} ]] && echo "未安装" && return 1
	local raw_version
	raw_version=$("${server_bin}" version 2>/dev/null || "${server_bin}" --version 2>/dev/null || "${server_bin}" -v 2>/dev/null || echo "unknown")
	normalizeVersion "${raw_version}"
}

getRemoteVersion(){
	local latest_release_url="https://api.github.com/repos/${repo_owner}/${repo_name}/releases/latest"
	curl -fsS --max-time 5 "${latest_release_url}" 2>/dev/null | grep -oE '"tag_name":\s*"[^"]+"' | head -n 1 | sed -E 's/.*"tag_name":\s*"//; s/"$//; s#^app/##' || echo "获取失败"
}

compareVersions(){
	local version1 version2
	version1=$(echo "$1" | sed 's/^v//')
	version2=$(echo "$2" | sed 's/^v//')
	[[ "${version1}" == "${version2}" ]] && return 1
	if printf '%s\n' "${version1}" "${version2}" | sort -V | head -1 | grep -q "^${version1}$"; then
		return 2
	else
		return 0
	fi
}

yaml_quote(){
	local val="$1"
	val=${val//\\/\\\\}
	val=${val//\"/\\\"}
	printf '"%s"' "$val"
}

strip_quotes(){
	echo "$1" | sed -E 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^"//; s/"$//'
}

firstDomainFromCSV(){
	echo "$1" | awk -F',' '{print $1}' | sed -E 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

extractCertServerName(){
	local cert_path="$1"
	local san_line
	local san_name
	local cn_name

	[[ -f "${cert_path}" ]] || { echo ""; return 1; }

	san_line=$(openssl x509 -in "${cert_path}" -noout -ext subjectAltName 2>/dev/null | tr '\n' ' ')
	san_name=$(echo "${san_line}" | grep -oE 'DNS:[^, ]+' | head -n 1 | sed 's/^DNS://')
	if [[ -n "${san_name}" ]]; then
		echo "${san_name}"
		return 0
	fi

	cn_name=$(openssl x509 -in "${cert_path}" -noout -subject 2>/dev/null | sed -E 's/^subject= *//' | sed -nE 's#.*CN=([^,/]+).*#\1#p' | head -n 1)
	echo "${cn_name}"
}

url_encode(){
	local raw="$1"
	local length=${#raw}
	local i c out hex
	out=""
	for ((i=0; i<length; i++)); do
		c="${raw:i:1}"
		case "${c}" in
			[a-zA-Z0-9.~_-]) out+="${c}" ;;
			*) printf -v hex '%%%02X' "'${c}"; out+="${hex}" ;;
		esac
	done
	echo "${out}"
}

pickRandomSni(){
	local count=${#sni_candidates[@]}
	local index=$((RANDOM % count))
	echo "${sni_candidates[${index}]}"
}

getDefaultSni(){
	if [[ -z "${hy_default_sni}" ]]; then
		hy_default_sni=$(pickRandomSni)
	fi
	echo "${hy_default_sni}"
}

setClientSni(){
	local default_sni
	local input_sni
	default_sni=$(getDefaultSni)
	echo -e "${Tip} 留空将从预置列表随机选择一个 SNI。"
	read -e -p "请输入 SNI (默认: ${default_sni}): " input_sni
	[[ -z "${input_sni}" ]] && input_sni="${default_sni}"
	while [[ "${input_sni}" =~ [[:space:]] ]]; do
		echo -e "${Error} SNI 不能包含空格，请重新输入。"
		read -e -p "请输入 SNI (默认: ${default_sni}): " input_sni
		[[ -z "${input_sni}" ]] && input_sni="${default_sni}"
	done
	hy_client_sni="${input_sni}"
}

extract_port(){
	local listen="$1"
	if [[ "${listen}" =~ :([0-9]{1,5}(-[0-9]{1,5})?)$ ]]; then
		echo "${BASH_REMATCH[1]}"
	else
		echo ""
	fi
}

detectListenMode(){
	local listen="$1"
	if [[ "${listen}" =~ ^0\.0\.0\.0: ]]; then
		echo "ipv4"
	elif [[ "${listen}" =~ ^\[\:\:\]: ]]; then
		echo "ipv6"
	else
		echo "default"
	fi
}

buildListenAddress(){
	local port_or_range="$1"
	local mode="$2"
	case "${mode}" in
		ipv4) echo "0.0.0.0:${port_or_range}" ;;
		ipv6) echo "[::]:${port_or_range}" ;;
		*) echo ":${port_or_range}" ;;
	esac
}

is_port_hopping(){
	local listen="$1"
	[[ "${listen}" =~ :[0-9]{1,5}-[0-9]{1,5}$ ]]
}

ensurePortHoppingDeps(){
	local listen="$1"
	if ! is_port_hopping "${listen}"; then
		return 0
	fi
	if command -v nft >/dev/null 2>&1 || command -v iptables >/dev/null 2>&1 || command -v ip6tables >/dev/null 2>&1; then
		return 0
	fi

	echo -e "${Info} 已启用端口跳跃，正在安装 nftables/iptables..."
	if [[ ${release} == "centos" ]]; then
		if command -v dnf >/dev/null 2>&1; then
			dnf install -y nftables || dnf install -y iptables
		else
			yum install -y nftables || yum install -y iptables
		fi
	else
		apt-get update
		apt-get install -y nftables || apt-get install -y iptables
	fi

	if ! command -v nft >/dev/null 2>&1 && ! command -v iptables >/dev/null 2>&1 && ! command -v ip6tables >/dev/null 2>&1; then
		echo -e "${Error} 未检测到 nft/iptables，请手动安装后再开启端口跳跃。"
		return 1
	fi

	return 0
}

ensureAcmeDependencies(){
	if [[ "${hy_tls_mode}" != "acme" ]]; then
		return 0
	fi
	if [[ -f /etc/ssl/certs/ca-certificates.crt || -f /etc/pki/tls/certs/ca-bundle.crt ]]; then
		return 0
	fi

	echo -e "${Info} 已启用 ACME，正在安装 ca-certificates..."
	if [[ ${release} == "centos" ]]; then
		if command -v dnf >/dev/null 2>&1; then
			dnf install -y ca-certificates
		else
			yum install -y ca-certificates
		fi
	else
		apt-get update
		apt-get install -y ca-certificates
	fi
	return 0
}

loadConfigInfo(){
	cfg_listen=""
	cfg_port=""
	cfg_auth_type=""
	cfg_password=""
	cfg_user=""
	cfg_userpass=""
	cfg_tls_mode=""
	cfg_acme_domains=""
	cfg_acme_email=""
	cfg_cert=""
	cfg_key=""
	cfg_obfs_type=""
	cfg_obfs_password=""
	cfg_masq_type=""
	cfg_masq_target=""
	cfg_masq_rewrite_host=""
	cfg_masq_insecure=""
	cfg_masq_x_forwarded=""
	cfg_masq_status=""
	cfg_client_sni=""

	local section=""
	local in_domains=0
	local in_userpass=0
	local in_masq_proxy=0
	local in_masq_file=0
	local in_masq_string=0
	local line

	while IFS= read -r line; do
		[[ -z "${line}" ]] && continue
		if [[ "${line}" =~ ^# ]]; then
			if [[ "${line}" =~ ^#[[:space:]]*client_sni: ]]; then
				cfg_client_sni=$(strip_quotes "${line#*:}")
			fi
			continue
		fi
		if [[ "${line}" =~ ^listen: ]]; then
			cfg_listen=$(strip_quotes "${line#listen:}")
			continue
		fi

		if [[ "${line}" =~ ^[^[:space:]] ]]; then
			section="${line%%:*}"
			in_domains=0
			in_userpass=0
			in_masq_proxy=0
			in_masq_file=0
			in_masq_string=0
		fi

		case "${section}" in
			acme)
				cfg_tls_mode="acme"
				if [[ "${line}" =~ ^[[:space:]]*domains: ]]; then
					in_domains=1
					continue
				fi
				if [[ "${line}" =~ ^[[:space:]]*email: ]]; then
					cfg_acme_email=$(strip_quotes "${line#*:}")
					in_domains=0
					continue
				fi
				if [[ ${in_domains} -eq 1 && "${line}" =~ ^[[:space:]]*-[[:space:]] ]]; then
					local dom
					dom=$(strip_quotes "${line#*-}")
					if [[ -z "${cfg_acme_domains}" ]]; then
						cfg_acme_domains="${dom}"
					else
						cfg_acme_domains="${cfg_acme_domains}, ${dom}"
					fi
				fi
				;;
			tls)
				cfg_tls_mode="tls"
				if [[ "${line}" =~ ^[[:space:]]*cert: ]]; then
					cfg_cert=$(strip_quotes "${line#*:}")
				fi
				if [[ "${line}" =~ ^[[:space:]]*key: ]]; then
					cfg_key=$(strip_quotes "${line#*:}")
				fi
				;;
			auth)
				if [[ "${line}" =~ ^[[:space:]]*type: ]]; then
					cfg_auth_type=$(strip_quotes "${line#*:}")
				fi
				if [[ "${line}" =~ ^[[:space:]]*password: ]]; then
					cfg_password=$(strip_quotes "${line#*:}")
				fi
				if [[ "${line}" =~ ^[[:space:]]*userpass: ]]; then
					in_userpass=1
					continue
				fi
				if [[ ${in_userpass} -eq 1 && "${line}" =~ : ]]; then
					local entry
					entry=$(echo "${line}" | sed -E 's/^[[:space:]]*//')
					cfg_user=$(echo "${entry}" | sed -E 's/^"?([^":]+)"?:.*/\1/')
					cfg_userpass=$(echo "${entry}" | sed -E 's/^[^:]+:[[:space:]]*"?([^"]*)"?.*/\1/')
					in_userpass=0
				fi
				;;
			obfs)
				if [[ "${line}" =~ ^[[:space:]]*type: ]]; then
					cfg_obfs_type=$(strip_quotes "${line#*:}")
				fi
				if [[ "${line}" =~ ^[[:space:]]*password: ]]; then
					cfg_obfs_password=$(strip_quotes "${line#*:}")
				fi
				;;
			masquerade)
				if [[ "${line}" =~ ^[[:space:]]*type: ]]; then
					cfg_masq_type=$(strip_quotes "${line#*:}")
				fi
				if [[ "${line}" =~ ^[[:space:]]*proxy: ]]; then
					in_masq_proxy=1
					in_masq_file=0
					in_masq_string=0
					continue
				fi
				if [[ "${line}" =~ ^[[:space:]]*file: ]]; then
					in_masq_file=1
					in_masq_proxy=0
					in_masq_string=0
					continue
				fi
				if [[ "${line}" =~ ^[[:space:]]*string: ]]; then
					in_masq_string=1
					in_masq_proxy=0
					in_masq_file=0
					continue
				fi
				if [[ ${in_masq_proxy} -eq 1 && "${line}" =~ ^[[:space:]]*url: ]]; then
					cfg_masq_target=$(strip_quotes "${line#*:}")
				fi
				if [[ ${in_masq_proxy} -eq 1 && "${line}" =~ ^[[:space:]]*rewriteHost: ]]; then
					cfg_masq_rewrite_host=$(strip_quotes "${line#*:}")
				fi
				if [[ ${in_masq_proxy} -eq 1 && "${line}" =~ ^[[:space:]]*insecure: ]]; then
					cfg_masq_insecure=$(strip_quotes "${line#*:}")
				fi
				if [[ ${in_masq_proxy} -eq 1 && "${line}" =~ ^[[:space:]]*xForwarded: ]]; then
					cfg_masq_x_forwarded=$(strip_quotes "${line#*:}")
				fi
				if [[ ${in_masq_file} -eq 1 && "${line}" =~ ^[[:space:]]*dir: ]]; then
					cfg_masq_target=$(strip_quotes "${line#*:}")
				fi
				if [[ ${in_masq_string} -eq 1 && "${line}" =~ ^[[:space:]]*content: ]]; then
					cfg_masq_target=$(strip_quotes "${line#*:}")
				fi
				if [[ ${in_masq_string} -eq 1 && "${line}" =~ ^[[:space:]]*statusCode: ]]; then
					cfg_masq_status=$(strip_quotes "${line#*:}")
				fi
				;;
		esac
	done < "${config_file}"

	cfg_port=$(extract_port "${cfg_listen}")
}

syncConfigToVars(){
	if [[ ! -f "${config_file}" ]]; then
		echo -e "${Error} 配置文件不存在：${config_file}"
		return 1
	fi
	loadConfigInfo

	hy_listen="${cfg_listen:-${hy_listen}}"
	hy_listen_mode=$(detectListenMode "${hy_listen}")
	hy_tls_mode="${cfg_tls_mode:-${hy_tls_mode}}"
	if [[ "${hy_tls_mode}" == "acme" ]]; then
		hy_acme_domains="${cfg_acme_domains}"
		hy_acme_email="${cfg_acme_email}"
	else
		hy_cert_path="${cfg_cert:-${hy_cert_path}}"
		hy_key_path="${cfg_key:-${hy_key_path}}"
	fi

	hy_auth_type="${cfg_auth_type:-${hy_auth_type}}"
	if [[ "${hy_auth_type}" == "password" ]]; then
		hy_password="${cfg_password}"
		hy_user=""
		hy_userpass=""
	else
		hy_user="${cfg_user}"
		hy_userpass="${cfg_userpass}"
		hy_password=""
	fi

	hy_obfs_enable="false"
	hy_obfs_type="salamander"
	hy_obfs_password=""
	if [[ -n "${cfg_obfs_type}" ]]; then
		hy_obfs_enable="true"
		hy_obfs_type="${cfg_obfs_type}"
		hy_obfs_password="${cfg_obfs_password}"
	fi

	hy_masquerade_enable="false"
	hy_masquerade_type="proxy"
	hy_masquerade_url=""
	hy_masquerade_dir=""
	hy_masquerade_string=""
	hy_masquerade_status="${default_masquerade_status}"
	hy_masquerade_rewrite_host="true"
	hy_masquerade_insecure="false"
	hy_masquerade_x_forwarded="false"
	if [[ -n "${cfg_masq_type}" ]]; then
		hy_masquerade_enable="true"
		hy_masquerade_type="${cfg_masq_type}"
		if [[ "${cfg_masq_type}" == "proxy" ]]; then
			hy_masquerade_url="${cfg_masq_target}"
			[[ -n "${cfg_masq_rewrite_host}" ]] && hy_masquerade_rewrite_host="${cfg_masq_rewrite_host}"
			[[ -n "${cfg_masq_insecure}" ]] && hy_masquerade_insecure="${cfg_masq_insecure}"
			[[ -n "${cfg_masq_x_forwarded}" ]] && hy_masquerade_x_forwarded="${cfg_masq_x_forwarded}"
		elif [[ "${cfg_masq_type}" == "file" ]]; then
			hy_masquerade_dir="${cfg_masq_target}"
		elif [[ "${cfg_masq_type}" == "string" ]]; then
			hy_masquerade_string="${cfg_masq_target}"
			[[ -n "${cfg_masq_status}" ]] && hy_masquerade_status="${cfg_masq_status}"
		fi
	fi

	hy_client_sni="${cfg_client_sni}"
}

buildHy2Uri(){
	local host="$1"
	local port="$2"
	local sni="$3"
	local insecure="$4"
	local label="$5"
	local auth=""
	local uri="hysteria2://"
	local query=""
	local params=()

	if [[ "${cfg_auth_type}" == "password" && -n "${cfg_password}" ]]; then
		auth=$(url_encode "${cfg_password}")
	elif [[ "${cfg_auth_type}" == "userpass" && -n "${cfg_user}" ]]; then
		auth="$(url_encode "${cfg_user}")"
		if [[ -n "${cfg_userpass}" ]]; then
			auth+="$(printf ':%s' "$(url_encode "${cfg_userpass}")")"
		fi
	fi

	if [[ -n "${auth}" ]]; then
		uri+="${auth}@"
	fi
	uri+="${host}"
	if [[ -n "${port}" ]]; then
		uri+="${port:+:${port}}"
	fi

	if [[ -n "${cfg_obfs_type}" ]]; then
		params+=("obfs=$(url_encode "${cfg_obfs_type}")")
	fi
	if [[ -n "${cfg_obfs_password}" ]]; then
		params+=("obfs-password=$(url_encode "${cfg_obfs_password}")")
	fi
	if [[ -n "${sni}" ]]; then
		params+=("sni=$(url_encode "${sni}")")
	fi
	if [[ "${insecure}" == "true" ]]; then
		params+=("insecure=1")
	else
		params+=("insecure=0")
	fi

	if [[ ${#params[@]} -gt 0 ]]; then
		query=$(IFS='&'; echo "${params[*]}")
		uri+="/?${query}"
	fi

	if [[ -n "${label}" ]]; then
		uri+="#$(url_encode "${label}")"
	fi

	echo "${uri}"
}

backupFile(){
	local target=$1
	local backup_path
	if [[ -f "${target}" ]]; then
		backup_path="${target}.bak.$(date +%Y%m%d_%H%M%S)"
		cp "${target}" "${backup_path}"
		echo -e "${Info} 已备份文件：${backup_path}"
	fi
}

generateSelfSignedCert(){
	local domain=$1
	mkdir -p "${install_dir}"
	chmod 700 "${install_dir}"

	if [[ -f "${cert_file}" ]]; then
		backupFile "${cert_file}"
	fi
	if [[ -f "${key_file}" ]]; then
		backupFile "${key_file}"
	fi

	echo -e "${Info} 正在为 ${domain} 生成自签名证书..."
	openssl req -x509 -newkey rsa:2048 -nodes -keyout "${key_file}" -out "${cert_file}" -days 3650 -subj "/CN=${domain}" >/dev/null 2>&1 || return 1
	chmod 600 "${key_file}"
	chmod 644 "${cert_file}"
}

writeConfig(){
	mkdir -p "${install_dir}"
	chmod 700 "${install_dir}"

	{
		if [[ -n "${hy_client_sni}" ]]; then
			echo "# client_sni: $(yaml_quote "${hy_client_sni}")"
		fi
		echo "listen: $(yaml_quote "${hy_listen}")"
		if [[ "${hy_tls_mode}" == "acme" ]]; then
			echo ""
			echo "acme:"
			echo "  domains:"
			local domains
			domains=$(echo "${hy_acme_domains}" | tr ',' ' ')
			for d in ${domains}; do
				[[ -n "${d}" ]] && echo "    - $(yaml_quote "${d}")"
			done
			echo "  email: $(yaml_quote "${hy_acme_email}")"
		else
			echo ""
			echo "tls:"
			echo "  cert: $(yaml_quote "${hy_cert_path}")"
			echo "  key: $(yaml_quote "${hy_key_path}")"
		fi

		echo ""
		echo "auth:"
		echo "  type: $(yaml_quote "${hy_auth_type}")"
		if [[ "${hy_auth_type}" == "password" ]]; then
			echo "  password: $(yaml_quote "${hy_password}")"
		else
			echo "  userpass:"
			echo "    $(yaml_quote "${hy_user}"): $(yaml_quote "${hy_userpass}")"
		fi

		if [[ "${hy_obfs_enable}" == "true" ]]; then
			echo ""
			echo "obfs:"
			echo "  type: ${hy_obfs_type}"
			echo "  ${hy_obfs_type}:"
			echo "    password: $(yaml_quote "${hy_obfs_password}")"
		fi

			if [[ "${hy_masquerade_enable}" == "true" ]]; then
				echo ""
				echo "masquerade:"
				echo "  type: ${hy_masquerade_type}"
			if [[ "${hy_masquerade_type}" == "proxy" ]]; then
				echo "  proxy:"
				echo "    url: $(yaml_quote "${hy_masquerade_url}")"
				echo "    rewriteHost: ${hy_masquerade_rewrite_host}"
				echo "    insecure: ${hy_masquerade_insecure}"
				echo "    xForwarded: ${hy_masquerade_x_forwarded}"
			elif [[ "${hy_masquerade_type}" == "file" ]]; then
				echo "  file:"
				echo "    dir: $(yaml_quote "${hy_masquerade_dir}")"
			elif [[ "${hy_masquerade_type}" == "string" ]]; then
				echo "  string:"
				echo "    content: $(yaml_quote "${hy_masquerade_string}")"
				echo "    statusCode: ${hy_masquerade_status}"
				fi
			fi

			echo ""
			echo "bandwidth:"
			echo "  up: 0 gbps"
			echo "  down: 0 gbps"
			echo ""
			echo "udpIdleTimeout: 90s"
		} > "${config_file}"
		chmod 600 "${config_file}"
}

setupService(){
	cat > "${service_path}" << EOF
[Unit]
Description=Hysteria Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${install_dir}
ExecStart=${server_bin} server
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
	systemctl daemon-reload
	systemctl enable hysteria-server.service >/dev/null 2>&1
	echo -e "${Info} Hysteria 服务配置完成！"
}

waitServiceRunning(){
	local action_name=$1
	local timeout=5
	local elapsed=0

	while [[ ${elapsed} -lt ${timeout} ]]; do
		sleep 1
		checkStatus
		if [[ "${status}" == "running" ]]; then
			echo -e "${Info} Hysteria ${action_name}成功！"
			return 0
		fi
		((elapsed++))
	done

	checkStatus
	if [[ "${status}" == "running" ]]; then
		echo -e "${Info} Hysteria ${action_name}成功！"
		return 0
	fi

	echo -e "${Error} Hysteria ${action_name}失败！"
	echo -e "${Error} 请使用 'systemctl status hysteria-server' 查看详细错误信息"
	journalctl -u hysteria-server -n 20 --no-pager 2>/dev/null
	return 1
}

setListen(){
	local default_port
	local listen_input
	local current_mode
	default_port="8443"
	current_mode="${hy_listen_mode}"
	[[ -z "${current_mode}" ]] && current_mode=$(detectListenMode "${hy_listen}")
	read -e -p "请输入监听端口(默认: ${default_port}): " listen_input
	[[ -z "${listen_input}" ]] && listen_input="${default_port}"
	if [[ "${listen_input}" =~ ^[0-9]+$ ]]; then
		if [[ ${listen_input} -ge 1 && ${listen_input} -le 65535 ]]; then
			hy_listen=$(buildListenAddress "${listen_input}" "${current_mode}")
		else
			echo -e "${Error} 端口不合法，已使用默认值 ${default_port}。"
			hy_listen=$(buildListenAddress "${default_port}" "${current_mode}")
		fi
	elif [[ "${listen_input}" =~ ^[0-9]+-[0-9]+$ ]]; then
		local start_port end_port
		start_port="${listen_input%-*}"
		end_port="${listen_input#*-}"
		if [[ ${start_port} -ge 1 && ${end_port} -le 65535 && ${start_port} -le ${end_port} ]]; then
			hy_listen=$(buildListenAddress "${listen_input}" "${current_mode}")
		else
			echo -e "${Error} 端口范围不合法，已使用默认值 ${default_port}。"
			hy_listen=$(buildListenAddress "${default_port}" "${current_mode}")
		fi
	else
		echo -e "${Error} 输入不合法，已使用默认值 ${default_port}。"
		hy_listen=$(buildListenAddress "${default_port}" "${current_mode}")
	fi
	echo -e "${Info} 监听端口: $(extract_port "${hy_listen}")"
}

setListenMode(){
	local mode_choice
	local current_mode
	local current_port

	if [[ "${hy_listen}" == realm://* ]]; then
		echo -e "${Error} Realms 模式不支持修改监听模式。"
		return 1
	fi

	current_mode="${hy_listen_mode}"
	[[ -z "${current_mode}" ]] && current_mode=$(detectListenMode "${hy_listen}")
	current_port=$(extract_port "${hy_listen}")
	[[ -z "${current_port}" ]] && current_port="8443"

	echo -e "请选择监听模式:\n${Green_font_prefix} 1.${Font_color_suffix} 默认\n${Green_font_prefix} 2.${Font_color_suffix} 仅 IPv4\n${Green_font_prefix} 3.${Font_color_suffix} 仅 IPv6"
	case "${current_mode}" in
		ipv4) read -e -p "(默认: 2): " mode_choice ;;
		ipv6) read -e -p "(默认: 3): " mode_choice ;;
		*) read -e -p "(默认: 1): " mode_choice ;;
	esac
	[[ -z "${mode_choice}" ]] && {
		case "${current_mode}" in
			ipv4) mode_choice="2" ;;
			ipv6) mode_choice="3" ;;
			*) mode_choice="1" ;;
		esac
	}

	case "${mode_choice}" in
		1) hy_listen_mode="default" ;;
		2) hy_listen_mode="ipv4" ;;
		3) hy_listen_mode="ipv6" ;;
		*)
			echo -e "${Error} 输入不合法，已保留当前监听模式。"
			hy_listen_mode="${current_mode}"
			;;
	esac

	hy_listen=$(buildListenAddress "${current_port}" "${hy_listen_mode}")
	echo -e "${Info} 当前监听地址: ${hy_listen}"
}

setAuth(){
	echo -e "请选择认证类型:\n${Green_font_prefix} 1.${Font_color_suffix} password\n${Green_font_prefix} 2.${Font_color_suffix} userpass"
	read -e -p "(默认: 1): " auth_choice
	[[ -z "${auth_choice}" ]] && auth_choice="1"
	if [[ "${auth_choice}" == "2" ]]; then
		hy_auth_type="userpass"
		read -e -p "请输入用户名: " hy_user
		while [[ -z "${hy_user}" ]]; do
			echo -e "${Error} 用户名不能为空。"
			read -e -p "请输入用户名: " hy_user
		done
		read -e -p "请输入密码: " hy_userpass
		while [[ -z "${hy_userpass}" ]]; do
			echo -e "${Error} 密码不能为空。"
			read -e -p "请输入密码: " hy_userpass
		done
	else
		hy_auth_type="password"
		read -e -p "请输入密码(默认: 随机生成): " hy_password
		[[ -z "${hy_password}" ]] && hy_password=$(generatePassword)
	fi
}

setTLSMode(){
	echo -e "请选择 TLS 模式:\n${Green_font_prefix} 1.${Font_color_suffix} ACME 自动证书\n${Green_font_prefix} 2.${Font_color_suffix} 已有证书\n${Green_font_prefix} 3.${Font_color_suffix} 自签名证书"
	read -e -p "(默认: 3): " tls_choice
	[[ -z "${tls_choice}" ]] && tls_choice="3"
	if [[ "${tls_choice}" == "2" ]]; then
		hy_tls_mode="tls"
		local detected_sni
		read -e -p "证书路径: " hy_cert_path
		read -e -p "私钥路径: " hy_key_path
		if [[ ! -f "${hy_cert_path}" || ! -f "${hy_key_path}" ]]; then
			echo -e "${Tip} 证书或私钥文件不存在，请确认路径是否正确。"
			hy_client_sni=""
		else
			detected_sni=$(extractCertServerName "${hy_cert_path}")
			if [[ -n "${detected_sni}" ]]; then
				hy_client_sni="${detected_sni}"
			else
				hy_client_sni=""
				echo -e "${Tip} 无法从证书读取 SNI，请确认该证书包含 SAN/CN。"
			fi
		fi
	elif [[ "${tls_choice}" == "3" ]]; then
		hy_tls_mode="tls"
		local default_cn
		default_cn=$(getDefaultSni)
		echo -e "${Tip} CN 用于证书名称，建议与客户端 SNI 一致；与代理 URL 无直接关系。"
		read -e -p "自签名证书域名(CN) (默认: ${default_cn}): " cert_domain
		[[ -z "${cert_domain}" ]] && cert_domain="${default_cn}"
		generateSelfSignedCert "${cert_domain}" || { echo -e "${Error} 证书生成失败"; return 1; }
		hy_cert_path="${cert_file}"
		hy_key_path="${key_file}"
		hy_client_sni="${cert_domain}"
	else
		hy_tls_mode="acme"
		local default_acme_domain
		local primary_acme_domain
		default_acme_domain=$(hostname -f 2>/dev/null || true)
		if [[ "${default_acme_domain}" != *.* ]]; then
			default_acme_domain="example.com"
			echo -e "${Tip} ACME 需要真实可解析域名，请替换默认值。"
		fi
		read -e -p "ACME 域名(多个用逗号分隔) (默认: ${default_acme_domain}): " hy_acme_domains
		[[ -z "${hy_acme_domains}" ]] && hy_acme_domains="${default_acme_domain}"
		read -e -p "ACME 邮箱: " hy_acme_email
		while [[ -z "${hy_acme_email}" ]]; do
			echo -e "${Error} 邮箱不能为空。"
			read -e -p "ACME 邮箱: " hy_acme_email
		done
		primary_acme_domain=$(firstDomainFromCSV "${hy_acme_domains}")
		if [[ -n "${primary_acme_domain}" ]]; then
			hy_client_sni="${primary_acme_domain}"
		fi
	fi
}

setObfs(){
	read -e -p "是否启用混淆? (y/N): " obfs_choice
	[[ -z "${obfs_choice}" ]] && obfs_choice="n"
	if [[ ${obfs_choice} == [Yy] ]]; then
		hy_obfs_enable="true"
		echo -e "请选择混淆类型:\n${Green_font_prefix} 1.${Font_color_suffix} salamander\n${Green_font_prefix} 2.${Font_color_suffix} gecko(实验性)"
		read -e -p "(默认: 1): " obfs_type_choice
		[[ -z "${obfs_type_choice}" ]] && obfs_type_choice="1"
		if [[ "${obfs_type_choice}" == "2" ]]; then
			hy_obfs_type="gecko"
		else
			hy_obfs_type="salamander"
		fi
		read -e -p "混淆密码(默认: 随机生成): " hy_obfs_password
		[[ -z "${hy_obfs_password}" ]] && hy_obfs_password=$(generatePassword)
	else
		hy_obfs_enable="false"
		hy_obfs_type="salamander"
	fi
}

setMasquerade(){
	read -e -p "是否启用伪装? (Y/n): " masq_choice
	[[ -z "${masq_choice}" ]] && masq_choice="y"
	if [[ ${masq_choice} == [Yy] ]]; then
		hy_masquerade_enable="true"
		echo -e "请选择伪装类型:\n${Green_font_prefix} 1.${Font_color_suffix} proxy\n${Green_font_prefix} 2.${Font_color_suffix} file\n${Green_font_prefix} 3.${Font_color_suffix} string"
		read -e -p "(默认: 1): " masq_type
		[[ -z "${masq_type}" ]] && masq_type="1"
		if [[ "${masq_type}" == "2" ]]; then
			hy_masquerade_type="file"
			read -e -p "请输入要提供的目录(默认: ${default_masquerade_dir}): " hy_masquerade_dir
			[[ -z "${hy_masquerade_dir}" ]] && hy_masquerade_dir="${default_masquerade_dir}"
		elif [[ "${masq_type}" == "3" ]]; then
			hy_masquerade_type="string"
			read -e -p "请输入字符串内容(默认: ${default_masquerade_string}): " hy_masquerade_string
			[[ -z "${hy_masquerade_string}" ]] && hy_masquerade_string="${default_masquerade_string}"
			read -e -p "状态码(默认: ${default_masquerade_status}): " hy_masquerade_status
			[[ -z "${hy_masquerade_status}" ]] && hy_masquerade_status="${default_masquerade_status}"
		else
			hy_masquerade_type="proxy"
			echo -e "${Tip} 代理 URL 用于伪装的内容来源，请填写可访问的网站。"
			read -e -p "请输入代理 URL (默认: ${default_masquerade_url}): " hy_masquerade_url
			[[ -z "${hy_masquerade_url}" ]] && hy_masquerade_url="${default_masquerade_url}"
			read -e -p "是否重写 Host? (Y/n): " rewrite_host
			[[ -z "${rewrite_host}" ]] && rewrite_host="y"
			if [[ ${rewrite_host} == [Yy] ]]; then
				hy_masquerade_rewrite_host="true"
			else
				hy_masquerade_rewrite_host="false"
			fi
		fi
	else
		hy_masquerade_enable="false"
	fi
}

startHysteria(){
	checkInstalledStatus
	checkStatus
	if [[ "${status}" == "running" ]]; then
		echo -e "${Info} Hysteria 已在运行！"
		return 0
	fi
	echo -e "${Info} 正在启动 Hysteria..."
	systemctl start hysteria-server.service
	waitServiceRunning "启动"
}

stopHysteria(){
	checkInstalledStatus
	checkStatus
	[[ ! "${status}" == "running" ]] && echo -e "${Error} Hysteria 没有运行，请检查！" && sleep 2s && startMenu
	systemctl stop hysteria-server.service
	echo -e "${Info} Hysteria 停止成功！"
	sleep 2s
	startMenu
}

restartHysteria(){
	checkInstalledStatus
	echo -e "${Info} 正在重启 Hysteria..."
	systemctl restart hysteria-server.service
	waitServiceRunning "重启"
	sleep 2s
	startMenu
}

applyConfigAndRestart(){
	writeConfig
	setupService
	echo -e "${Info} 正在重启 Hysteria..."
	systemctl restart hysteria-server.service
	waitServiceRunning "重启"
}

viewStatus(){
	checkInstalledStatus
	systemctl status hysteria-server.service
	echo
	read -e -p "按 Enter 继续..."
	startMenu
}

readConfigSummary(){
	local in_auth=0
	local in_masq=0
	local in_obfs=0
	local in_tls=0
	local in_acme=0
	local line
	local listen=""
	local auth_type=""
	local tls_mode=""

	while IFS= read -r line; do
		if [[ "${line}" =~ ^listen: ]]; then
			listen=$(echo "${line}" | sed -E 's/^listen:\s*//; s/^"//; s/"$//')
		fi
		if [[ "${line}" =~ ^acme: ]]; then
			in_acme=1
			in_tls=0
			tls_mode="acme"
		fi
		if [[ "${line}" =~ ^tls: ]]; then
			in_tls=1
			in_acme=0
			tls_mode="tls"
		fi
		if [[ "${line}" =~ ^auth: ]]; then
			in_auth=1
			continue
		fi
		if [[ "${line}" =~ ^obfs: ]]; then
			in_obfs=1
			continue
		fi
		if [[ "${line}" =~ ^masquerade: ]]; then
			in_masq=1
			continue
		fi

		if [[ ${in_auth} -eq 1 && "${line}" =~ ^[[:space:]]*type: ]]; then
			auth_type=$(echo "${line}" | sed -E 's/^\s*type:\s*//; s/^"//; s/"$//')
			in_auth=0
		fi
		done < "${config_file}"

	echo "${listen}|${tls_mode}|${auth_type}"
}

viewConfig(){
	checkInstalledStatus
	if [[ ! -f "${config_file}" ]]; then
		echo -e "${Error} 配置文件不存在：${config_file}"
		read -e -p "按 Enter 继续..."
		startMenu
	fi

	local public_host
	local port_display
	local auth_display
	local sni_value
	local insecure_value
	local obfs_enabled
	local masq_enabled
	local uri
	local uri_note
	local node_name
	local cert_subject
	local cert_issuer
	local surge_line
	local listen_mode_display

	public_host=$(detectPublicHost)
	loadConfigInfo

	port_display="${cfg_port:-未知}"
	if [[ "${cfg_listen}" == realm://* ]]; then
		port_display="Realm"
	fi

	sni_value=""
	cert_subject=""
	cert_issuer=""
	if [[ "${cfg_tls_mode}" == "tls" && -f "${cfg_cert}" ]]; then
		cert_subject=$(openssl x509 -in "${cfg_cert}" -noout -subject 2>/dev/null | sed -E 's/^subject= *//')
		cert_issuer=$(openssl x509 -in "${cfg_cert}" -noout -issuer 2>/dev/null | sed -E 's/^issuer= *//')
	fi
	if [[ "${cfg_tls_mode}" == "acme" && -n "${cfg_acme_domains}" ]]; then
		sni_value=$(firstDomainFromCSV "${cfg_acme_domains}")
	elif [[ "${cfg_tls_mode}" == "tls" && -n "${cfg_cert}" ]]; then
		sni_value=$(extractCertServerName "${cfg_cert}")
		if [[ -z "${sni_value}" && -n "${cfg_client_sni}" ]]; then
			sni_value="${cfg_client_sni}"
		fi
	elif [[ -n "${cfg_client_sni}" ]]; then
		sni_value="${cfg_client_sni}"
	fi

	insecure_value="false"
	if [[ -n "${cert_subject}" && -n "${cert_issuer}" && "${cert_subject}" == "${cert_issuer}" ]]; then
		insecure_value="true"
	fi

	if [[ "${cfg_listen}" == realm://* ]]; then
		listen_mode_display="Realm"
	else
		case "$(detectListenMode "${cfg_listen}")" in
			ipv4) listen_mode_display="仅 IPv4" ;;
			ipv6) listen_mode_display="仅 IPv6" ;;
			*) listen_mode_display="默认" ;;
		esac
	fi

	obfs_enabled="false"
	[[ -n "${cfg_obfs_type}" ]] && obfs_enabled="true"
	masq_enabled="false"
	[[ -n "${cfg_masq_type}" ]] && masq_enabled="true"

	uri=""
	uri_note=""
	if [[ "${cfg_listen}" == realm://* ]]; then
		uri_note="Realms 模式请参考文档手动配置"
	else
		node_name="${HOSTNAME:-$(hostname)}"
		uri=$(buildHy2Uri "${public_host}" "${cfg_port}" "${sni_value}" "${insecure_value}" "${node_name}")
	fi

	clear && echo
	echo -e "Hysteria 服务端配置信息："
	echo -e "—————————————————————————"
	echo -e " 服务地址\t: ${Green_font_prefix}${public_host}${Font_color_suffix}"
	echo -e " 监听模式\t: ${Green_font_prefix}${listen_mode_display:-未知}${Font_color_suffix}"
	echo -e " 端口\t\t: ${Green_font_prefix}${port_display}${Font_color_suffix}"
	echo -e " 认证类型\t: ${Green_font_prefix}${cfg_auth_type:-未知}${Font_color_suffix}"
	if [[ "${cfg_auth_type}" == "password" ]]; then
		echo -e " 密码\t\t: ${Green_font_prefix}${cfg_password:-未记录}${Font_color_suffix}"
	elif [[ "${cfg_auth_type}" == "userpass" ]]; then
		echo -e " 用户名\t\t: ${Green_font_prefix}${cfg_user:-未记录}${Font_color_suffix}"
		echo -e " 密码\t\t: ${Green_font_prefix}${cfg_userpass:-未记录}${Font_color_suffix}"
	fi
	echo -e " TLS 模式\t: ${Green_font_prefix}${cfg_tls_mode:-未知}${Font_color_suffix}"
	if [[ "${cfg_tls_mode}" == "acme" ]]; then
		echo -e " ACME 域名\t: ${Green_font_prefix}${cfg_acme_domains:-未设置}${Font_color_suffix}"
		echo -e " ACME 邮箱\t: ${Green_font_prefix}${cfg_acme_email:-未设置}${Font_color_suffix}"
	else
		echo -e " 证书路径\t: ${Green_font_prefix}${cfg_cert:-未设置}${Font_color_suffix}"
		echo -e " 私钥路径\t: ${Green_font_prefix}${cfg_key:-未设置}${Font_color_suffix}"
	fi
	echo -e " SNI\t\t: ${Green_font_prefix}${sni_value:-未设置}${Font_color_suffix}"
	echo -e " 跳过证书验证\t: ${Green_font_prefix}${insecure_value}${Font_color_suffix}"
	echo -e " 混淆\t\t: ${Green_font_prefix}${obfs_enabled}${Font_color_suffix}"
	if [[ "${obfs_enabled}" == "true" ]]; then
		echo -e " 混淆类型\t: ${Green_font_prefix}${cfg_obfs_type}${Font_color_suffix}"
		echo -e " 混淆密码\t: ${Green_font_prefix}${cfg_obfs_password:-未记录}${Font_color_suffix}"
	fi
	echo -e " 伪装\t\t: ${Green_font_prefix}${masq_enabled}${Font_color_suffix}"
	if [[ "${masq_enabled}" == "true" ]]; then
		echo -e " 伪装类型\t: ${Green_font_prefix}${cfg_masq_type}${Font_color_suffix}"
		echo -e " 伪装目标\t: ${Green_font_prefix}${cfg_masq_target:-未设置}${Font_color_suffix}"
	fi
	echo -e " 配置文件\t: ${Green_font_prefix}${config_file}${Font_color_suffix}"
	echo -e "—————————————————————————"
	echo -e "${Info} 协议链接："
	if [[ -n "${uri}" ]]; then
		echo -e "${uri}\n"
	else
		echo -e "${Tip} ${uri_note}\n"
	fi
	echo -e "${Info} Surge 配置："
	if [[ "${cfg_listen}" == realm://* ]]; then
		echo -e "${Tip} ${uri_note}"
	else
		surge_line="${node_name} = hysteria2, ${public_host}, ${cfg_port}"
		if [[ "${cfg_auth_type}" == "password" ]]; then
			surge_line+=", password=${cfg_password}"
		elif [[ "${cfg_auth_type}" == "userpass" ]]; then
			surge_line+=", username=${cfg_user}, password=${cfg_userpass}"
		fi
		if [[ -n "${surge_ecn}" ]]; then
			surge_line+=", ecn=${surge_ecn}"
		fi
		if [[ "${insecure_value}" == "true" ]]; then
			surge_line+=", skip-cert-verify=true"
		else
			surge_line+=", skip-cert-verify=false"
		fi
		if [[ -n "${sni_value}" ]]; then
			surge_line+=", sni=${sni_value}"
		fi
		if [[ -n "${cfg_obfs_type}" && -n "${cfg_obfs_password}" ]]; then
			if [[ "${cfg_obfs_type}" == "gecko" ]]; then
				surge_line+=", gecko-password=${cfg_obfs_password}"
			else
				surge_line+=", salamander-password=${cfg_obfs_password}"
			fi
		fi
		echo -e "${surge_line}"
	fi
	echo -e "—————————————————————————"
	read -e -p "按 Enter 继续..."
	startMenu
}

installHysteria(){
	checkRoot
	[[ -e ${server_bin} ]] && echo -e "${Error} 检测到 Hysteria 已安装，请先卸载旧版再安装新版!" && sleep 2s && startMenu
	echo -e "${Info} 开始设置配置..."
	setListen
	ensurePortHoppingDeps "${hy_listen}" || { sleep 2s; startMenu; return 1; }
	setAuth
	setTLSMode || { sleep 2s; startMenu; return 1; }
	ensureAcmeDependencies || { sleep 2s; startMenu; return 1; }
	setObfs
	setMasquerade
	echo -e "${Info} 开始安装依赖..."
	checkDependencies
	installDependencies
	echo -e "${Info} 开始下载/安装..."
	asset_name=$(detectReleaseAsset)
	downloadRelease "${asset_name}" || { sleep 2s; startMenu; return 1; }
	echo -e "${Info} 开始写入配置文件..."
	writeConfig
	echo -e "${Info} 开始安装服务脚本..."
	setupService
	echo -e "${Info} 开始启动服务..."
	startHysteria || { sleep 2s; startMenu; return 1; }
	echo -e "${Info} 安装完成"
	sleep 1s
	viewConfig
}

updateHysteria(){
	checkInstalledStatus
	checkDependencies

	echo -e "${Info} 正在检测版本..."
	local local_version remote_version
	local_version=$(getLocalVersion)
	remote_version=$(getRemoteVersion)

	[[ -z "${local_version}" ]] && local_version="未知版本"
	echo -e "${Info} 本地版本：${local_version}"
	echo -e "${Info} 最新版本：${remote_version}"

	if [[ "${remote_version}" == "获取失败" ]]; then
		echo -e "${Error} 获取远程版本失败，请稍后重试。"
		sleep 2s
		startMenu
		return 1
	fi

	compareVersions "${local_version}" "${remote_version}"
	if [[ $? -eq 1 ]]; then
		echo -e "${Tip} 已是最新版本，无需更新。"
		sleep 2s
		startMenu
		return 0
	fi

	echo "确定要更新 Hysteria 服务端 ? (y/N)"
	read -e -p "(默认: n): " confirm
	[[ -z "${confirm}" ]] && confirm="n"
	if [[ ${confirm} != [Yy] ]]; then
		echo -e "${Info} 已取消更新"
		sleep 2s
		startMenu
		return 0
	fi

	local backup_bin="${server_bin}.backup.$(date +%Y%m%d_%H%M%S)"
	cp "${server_bin}" "${backup_bin}"

	echo -e "${Info} 开始更新 Hysteria 服务端..."
	systemctl stop hysteria-server.service >/dev/null 2>&1 || true
	asset_name=$(detectReleaseAsset)
	if downloadRelease "${asset_name}"; then
		systemctl daemon-reload
		startHysteria
		if [[ $? -eq 0 ]]; then
			echo -e "${Info} 更新完成（${local_version} -> ${remote_version}）。"
			sleep 2s
			startMenu
			return 0
		fi
	fi

	echo -e "${Error} 更新失败，开始回滚旧版本..."
	cp "${backup_bin}" "${server_bin}"
	systemctl start hysteria-server.service >/dev/null 2>&1 || true
	echo -e "${Tip} 已回滚到旧版本：${backup_bin}"
	sleep 2s
	startMenu
}

modifyConfig(){
	checkInstalledStatus
	echo -e "${Info} 开始重新配置 Hysteria..."
	setListen
	ensurePortHoppingDeps "${hy_listen}" || { sleep 2s; startMenu; return 1; }
	setListenMode || { sleep 2s; startMenu; return 1; }
	ensurePortHoppingDeps "${hy_listen}" || { sleep 2s; startMenu; return 1; }
	setAuth
	setTLSMode || { sleep 2s; startMenu; return 1; }
	ensureAcmeDependencies || { sleep 2s; startMenu; return 1; }
	setObfs
	setMasquerade
	applyConfigAndRestart || { sleep 2s; startMenu; return 1; }
	echo -e "${Info} 配置修改完成。"
	sleep 2s
	viewConfig
}

modifyListen(){
	checkInstalledStatus
	syncConfigToVars || { sleep 2s; startMenu; return 1; }
	setListen
	ensurePortHoppingDeps "${hy_listen}" || { sleep 2s; startMenu; return 1; }
	applyConfigAndRestart || { sleep 2s; startMenu; return 1; }
	echo -e "${Info} 监听地址修改完成。"
	sleep 2s
	startMenu
}

modifyListenMode(){
	checkInstalledStatus
	syncConfigToVars || { sleep 2s; startMenu; return 1; }
	setListenMode || { sleep 2s; startMenu; return 1; }
	ensurePortHoppingDeps "${hy_listen}" || { sleep 2s; startMenu; return 1; }
	applyConfigAndRestart || { sleep 2s; startMenu; return 1; }
	echo -e "${Info} 监听模式修改完成。"
	sleep 2s
	startMenu
}

modifyAuth(){
	checkInstalledStatus
	syncConfigToVars || { sleep 2s; startMenu; return 1; }
	setAuth
	applyConfigAndRestart || { sleep 2s; startMenu; return 1; }
	echo -e "${Info} 认证信息修改完成。"
	sleep 2s
	startMenu
}

modifyTLS(){
	checkInstalledStatus
	syncConfigToVars || { sleep 2s; startMenu; return 1; }
	setTLSMode || { sleep 2s; startMenu; return 1; }
	ensureAcmeDependencies || { sleep 2s; startMenu; return 1; }
	applyConfigAndRestart || { sleep 2s; startMenu; return 1; }
	echo -e "${Info} TLS 配置修改完成。"
	sleep 2s
	startMenu
}

modifyObfs(){
	checkInstalledStatus
	syncConfigToVars || { sleep 2s; startMenu; return 1; }
	setObfs
	applyConfigAndRestart || { sleep 2s; startMenu; return 1; }
	echo -e "${Info} 混淆配置修改完成。"
	sleep 2s
	startMenu
}

modifyMasquerade(){
	checkInstalledStatus
	syncConfigToVars || { sleep 2s; startMenu; return 1; }
	setMasquerade
	applyConfigAndRestart || { sleep 2s; startMenu; return 1; }
	echo -e "${Info} 伪装配置修改完成。"
	sleep 2s
	startMenu
}

setConfig(){
	checkInstalledStatus
	echo && echo -e "请输入要操作配置项的序号，然后回车
==============================
 ${Green_font_prefix}1.${Font_color_suffix} 修改 监听端口
 ${Green_font_prefix}2.${Font_color_suffix} 修改 监听模式
 ${Green_font_prefix}3.${Font_color_suffix} 修改 认证信息
 ${Green_font_prefix}4.${Font_color_suffix} 修改 TLS 配置
 ${Green_font_prefix}5.${Font_color_suffix} 修改 混淆配置
 ${Green_font_prefix}6.${Font_color_suffix} 修改 伪装配置
 ${Green_font_prefix}7.${Font_color_suffix} 修改 全部配置
==============================" && echo
	read -e -p "(默认: 取消): " modify
	[[ -z "${modify}" ]] && echo "已取消..." && sleep 2s && startMenu
	case "${modify}" in
		1)
			modifyListen
			;;
		2)
			modifyListenMode
			;;
		3)
			modifyAuth
			;;
		4)
			modifyTLS
			;;
		5)
			modifyObfs
			;;
		6)
			modifyMasquerade
			;;
		7)
			modifyConfig
			;;
		*)
			echo -e "${Error} 请输入正确数字${Yellow_font_prefix}[1-7]${Font_color_suffix}"
			sleep 2s
			setConfig
			;;
	esac
}

uninstallHysteria(){
	checkRoot
	if [[ ! -e ${server_bin} && ! -e ${service_path} && ! -e ${install_dir} ]]; then
		echo -e "${Tip} 当前未检测到 Hysteria 安装。"
		sleep 2s
		startMenu
		return 0
	fi

	echo "确定要卸载 Hysteria 服务端 ? (y/N)"
	read -e -p "(默认: n): " confirm
	[[ -z "${confirm}" ]] && confirm="n"
	if [[ ${confirm} == [Yy] ]]; then
		systemctl stop hysteria-server.service >/dev/null 2>&1 || true
		systemctl disable hysteria-server.service >/dev/null 2>&1 || true
		rm -f "${service_path}"
		systemctl daemon-reload >/dev/null 2>&1 || true
		rm -f "${server_bin}"
		rm -rf "${install_dir}"
		echo -e "${Info} Hysteria 服务端卸载完成！"
	else
		echo -e "${Info} 卸载已取消..."
	fi
	sleep 2s
	startMenu
}

updateShell(){
	local sh_new_ver
	local script_path="${script_dir}/${script_name}"
	local tmp_script

	checkDependencies
	echo -e "当前版本为 [ ${sh_ver} ]，开始检测最新版本..."
	sh_new_ver=$(curl -fsSL --max-time 15 "${shell_url}" 2>/dev/null | grep 'sh_ver="' | awk -F "=" '{print $NF}' | sed 's/\"//g' | head -1)
	[[ -z ${sh_new_ver} ]] && echo -e "${Error} 检测最新版本失败！" && sleep 2s && startMenu
	if [[ ${sh_new_ver} != ${sh_ver} ]]; then
		echo -e "发现新版本[ ${sh_new_ver} ]，是否更新？[Y/n]"
		read -p "(默认: y): " yn
		[[ -z "${yn}" ]] && yn="y"
		if [[ ${yn} == [Yy] ]]; then
			tmp_script=$(mktemp)
			if curl -fsSL --max-time 60 "${shell_url}" -o "${tmp_script}"; then
				mv "${tmp_script}" "${script_path}" && chmod +x "${script_path}"
				echo -e "脚本已更新为最新版本[ ${sh_new_ver} ]！"
				echo -e "3s后执行新脚本"
				sleep 3s
				exec bash "${script_path}"
			else
				rm -f "${tmp_script}"
				echo -e "${Error} 脚本下载失败！"
				sleep 2s
				startMenu
			fi
		else
			echo -e "已取消..."
			sleep 2s
			startMenu
		fi
	else
		echo -e "当前已是最新版本[ ${sh_new_ver} ]！"
		sleep 2s
		startMenu
	fi
}

startMenu(){
	clear
	checkRoot
	checkSys
	sysArch

	echo && echo -e "
==============================
Hysteria 2 服务端管理脚本 ${Red_font_prefix}[v${sh_ver}]${Font_color_suffix}
==============================
 ${Green_font_prefix} 0.${Font_color_suffix} 检查脚本版本
------------------------------
 ${Green_font_prefix} 1.${Font_color_suffix} 安装 Hysteria 服务端
 ${Green_font_prefix} 2.${Font_color_suffix} 卸载 Hysteria 服务端
 ${Green_font_prefix} 3.${Font_color_suffix} 更新 Hysteria 服务端
------------------------------
 ${Green_font_prefix} 4.${Font_color_suffix} 启动 Hysteria 服务端
 ${Green_font_prefix} 5.${Font_color_suffix} 停止 Hysteria 服务端
 ${Green_font_prefix} 6.${Font_color_suffix} 重启 Hysteria 服务端
------------------------------
 ${Green_font_prefix} 7.${Font_color_suffix} 修改配置信息
 ${Green_font_prefix} 8.${Font_color_suffix} 查看配置信息
 ${Green_font_prefix} 9.${Font_color_suffix} 查看运行状态
------------------------------
 ${Green_font_prefix}00.${Font_color_suffix} 退出脚本"

	echo "==============================" && echo
	if [[ -e ${server_bin} ]]; then
		checkStatus
		if [[ "${status}" == "running" ]]; then
			echo -e " 当前状态: ${Green_font_prefix}已安装${Font_color_suffix}并${Green_font_prefix}已启动${Font_color_suffix}"
		else
			echo -e " 当前状态: ${Green_font_prefix}已安装${Font_color_suffix}但${Red_font_prefix}未启动${Font_color_suffix}"
		fi
	else
		echo -e " 当前状态: ${Red_font_prefix}未安装${Font_color_suffix}"
	fi
	echo

	read -e -p " 请输入数字[0-9/00]: " num
	case "$num" in
		0)
			updateShell
			;;
		1)
			installHysteria
			;;
		2)
			uninstallHysteria
			;;
		3)
			updateHysteria
			;;
		4)
			startHysteria
			sleep 2s
			startMenu
			;;
		5)
			stopHysteria
			;;
		6)
			restartHysteria
			;;
		7)
			setConfig
			;;
		8)
			viewConfig
			;;
		9)
			viewStatus
			;;
		00)
			exit 1
			;;
		*)
			echo -e "请输入正确数字"
			sleep 2s
			startMenu
			;;
	esac
}

startMenu
