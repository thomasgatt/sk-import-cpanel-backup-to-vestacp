#!/bin/bash
# Author / Idea: Maks Usmanov - Skamasle and good people who help to improve:
# Thanks to https://github.com/Skamasle/sk-import-cpanel-backup-to-vestacp/graphs/contributors
# Github: https://github.com/Skamasle/sk-import-cpanel-backup-to-vestacp
# Run at your own risk
# This script take cpanel full backup and import it in vestacp account
# This script can import databases and database users and password,
# Import domains, subdomains and website files
# This script import also mail accounts and mails into accounts if previous cpanel run dovecot
# Mail password not are restored this was reset by new one.
###########
# If you need restore main database user read line 160 or above
###########
if [ ! -e /usr/bin/rsync ] || [ ! -e /usr/bin/file ] ; then
	echo "#######################################"
	echo "rsync not installed, try install it"
	echo "This script need: rsync, file"
	echo "#######################################"
	if  [ -e /etc/redhat-release ]; then
		echo "Run: yum install rsync file"
	else
		echo "Run: apt-get install rsync file"
	fi
	exit 3
fi
# Put this to 0 if you want use bash -x to debug it
sk_debug=1
sk_vesta_package=default
#
# Only for gen_password but I dont like it, a lot of lt
# maybe will use it for other functions :)
source /usr/local/vesta/func/main.sh
sk_file=$1
sk_tmp=sk_tmp
# I see than this is stupid, not know why is here.
sk_file_name=$(ls $sk_file)
tput setaf 2
echo "Checking provided file..."
tput sgr0
if file $sk_file |grep -q -c "gzip compressed data," ; then
	tput setaf 2
	echo "OK - Gziped File"
	tput sgr0
	if [ ! -d /root/${sk_tmp} ]; then
		echo "Creating tmp.."
		mkdir /root/${sk_tmp}
	fi
	echo "Extracting backup..."
	if [ "$sk_debug" != 0 ]; then
		tar xzvf $sk_file -C /root/${sk_tmp} 2>&1 |
     		   while read sk_extracted_file; do
       				ex=$((ex+1))
       				echo -en "wait... $ex files extracted\r"
       		   done
		else
			tar xzf $sk_file -C /root/${sk_tmp}
	fi
		if [ $? -eq 0 ];then
			tput setaf 2
			echo "Backup extracted without errors..."
			tput sgr0
		else
			echo "Error on backup extraction, check your file, try extract it manually"
			echo "Remove tmp"
			rm -rf "/root/${sk_tmp}"
			exit 1
		fi
	else
	echo "Error 3 not-gzip - no stantard cpanel backup provided of file not installed ( Try yum install file, or apt-get install file )"
	rm -rf "/root/${sk_tmp}"
	exit 3
fi
cd /root/${sk_tmp}/*
sk_importer_in=$(pwd)
echo "Access tmp directory $sk_importer_in"
echo "Get prefix..."
sk_dead_prefix=$(cat meta/dbprefix)
if [ $sk_dead_prefix = 1 ]; then
	echo "Error 666 - I dont like your prefix, I dont want do this job"
	exit 666
else
	echo "I like your prefix, start working"
fi
main_domain1=$(grep main_domain userdata/main |cut -d " " -f2)
if [ "$(ls -A mysql)" ]; then
	sk_cp_user=$(ls mysql |grep sql | grep -v roundcube.sql |head -n1 |cut -d "_" -f1)
	if [ -z "$sk_cp_user" ]; then
		 	sk_cp_user=$(grep "user:" userdata/${main_domain1} | cut -d " " -f2)
	fi
	echo "$sk_cp_user" > sk_db_prefix
	tput setaf 2
	echo "Get user: $sk_cp_user"
	tput sgr0
	sk_restore_dbs=0
else
	sk_restore_dbs=1
# get real cPanel user if no databases exist
	sk_cp_user=$(grep "user:" userdata/${main_domain1} | cut -d " " -f2)
fi
# So get real user, may be we need it after -- oh yes, not remember where but this save my day march 19 2017 on 0.5
sk_real_cp_user=$(grep "user:" userdata/${main_domain1} | cut -d " " -f2)

skaddons=$(cat addons |cut -d "=" -f1)
sed -i 's/_/./g; s/=/ /g' addons
echo "Converting addons domains, subdomains and some other fun"
cp sds sk_sds
cp sds2 sk_sds2
sed -i 's/_/./g' sk_sds
sed -i 's/public_html/public@html/g; s/_/./g; s/public@html/public_html/g; s/=/ /g; s/$sk_default_sub/@/g' sk_sds2
cat addons | while read sk_addon_domain sk_addon_sub
do
	echo "Converting default subdomain: $sk_addon_sub in domain: $sk_addon_domain"
	sed -i -e "s/$sk_addon_sub/$sk_addon_domain/g" sk_sds
	sed -i -e "s/$sk_addon_sub/$sk_addon_domain/g" sk_sds2
	mv userdata/$sk_addon_sub userdata/${sk_addon_domain}
done

tput setaf 2
echo "Start restoring domains"
tput sgr0
function get_domain_path() {
		while read sk_domain path
	do
		if [ -e userdata/${sk_domain} ];then
			/usr/local/vesta/bin/v-add-domain $sk_cp_user $sk_domain
			echo "Restoring $sk_domain..."
			rm -f /home/${sk_cp_user}/web/${sk_domain}/public_html/index.html
			if [ "$sk_debug" != 0 ]; then
				rsync -av homedir/${path}/ /home/${sk_cp_user}/web/${sk_domain}/public_html 2>&1 |
    			while read sk_file_dm; do
       			 	sk_sync=$((sk_sync+1))
       			 	echo -en "-- $sk_sync restored files\r"
				done
			echo " "
			else
				rsync homedir/${path}/ /home/${sk_cp_user}/web/${sk_domain}/public_html
			fi
			chown $sk_cp_user:$sk_cp_user -R /home/${sk_cp_user}/web/${sk_domain}/public_html
			chmod 751 /home/${sk_cp_user}/web/${sk_domain}/public_html
			echo "$sk_domain" >> exclude_path
		fi
done

}
get_domain_path < sk_sds2

/usr/local/vesta/bin/v-add-domain $sk_cp_user $main_domain1
# need it for restore main domain
if [ ! -e exclude_path ];then
	touch exclude_path
fi
echo "Restore main domain: $main_domain1"
rm -f /home/${sk_cp_user}/web/${main_domain1}/public_html/index.html
if [ "$sk_debug" != 0 ]; then
	rsync -av --exclude-from='exclude_path' homedir/public_html/ /home/${sk_cp_user}/web/${main_domain1}/public_html 2>&1 |
    		while read sk_file_dm; do
       			 sk_sync=$((sk_sync+1))
       			 echo -en "-- $sk_sync restored files\r"
			done
		echo " "
else
	rsync --exclude-from='exclude_path' homedir/public_html/ /home/${sk_cp_user}/web/${main_domain1}/public_html 2>&1
fi
chown $sk_cp_user:$sk_cp_user -R /home/${sk_cp_user}/web/${main_domain1}/public_html
chmod 751 /home/${sk_cp_user}/web/${main_domain1}/public_html
rm -f sk_sds2 sk_sds

##################
# mail
tput setaf 2
echo "Start Restoring Mails"
tput sgr0
sk_cod=$(date +%s) # Just for numbers and create another file if acccount was restored before.
sk_mdir=${sk_importer_in}/homedir/mail
cd $sk_mdir
for sk_maild in $(ls -1)
do
if [[ "$sk_maild" != "cur" && "$sk_maild" != "new" && "$sk_maild" != "tmp"  ]]; then
	if [ -d "$sk_maild" ]; then
		for sk_mail_account in $(ls $sk_maild/)
		 do

					echo "Create and restore mail account: $sk_mail_account@$sk_maild"
					sk_mail_pass1=$(generate_password)
					/usr/local/vesta/bin/v-add-mail-account $sk_cp_user $sk_maild $sk_mail_account $sk_mail_pass1
					mv ${sk_maild}/${sk_mail_account} /home/${sk_cp_user}/mail/${sk_maild}
					chown ${sk_cp_user}:mail -R /home/${sk_cp_user}/mail/${sk_maild}
					echo "${sk_mail_account}@${sk_maild} | $sk_mail_pass1"	>> /root/sk_mail_password_${sk_cp_user}-${sk_cod}
		done
	fi
#else
# this only detect default dirs account new, cur, tmp etc
# maybe can do something with this, but on most cpanel default account have only spam.
fi
done
echo "All mail accounts restored"

echo "Remove tmp files"
rm -rf "/root/${sk_tmp}"
tput setaf 4
echo "##############################"
echo "cPanel Backup restored"
echo "Review your content and report any fail"
echo "I reset mail password not posible restore it yet."
echo "Check your new passwords runing: cat /root/sk_mail_password_${sk_cp_user}-${sk_cod}"
echo "##############################"
tput sgr0
