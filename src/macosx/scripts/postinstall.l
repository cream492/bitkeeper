/*
 * Post-install L script for BitKeeper's OS X package installer.
 * This script is called by the shell script "postinstall" in
 * the same directory.
 */

int	noprompt, rc;
string	err, newbk;
FILE	logf;

void	create_bklink(void);
void	log(FMT fmt, ...args);
void	rm_oldbk(string path);
string	runit(string cmd);

int
main(_argused int ac, _argused string av[], string env{string})
{
	string	dotbk, dstroot, home, oldbk, out, path, paths[], tmp, user;

	wm("withdraw", ".");
	noprompt = exists("/tmp/_bk_install_no_prompt");

	/*
	 * The OS X installer sets DSTROOT to the path to the install
	 * directory desired by the user. Bail if it's not set.
	 */
	dstroot = getenv("DSTROOT");
	log("bk installer starting: dstroot ${dstroot} noprompt ${noprompt}");
	unless (dstroot) exit(1);
	newbk = "${dstroot}/BitKeeper.app/Contents/Resources/bitkeeper/bk";
	runit("'${newbk}' version");  // for the install log

	/*
	 * Flush any leases held by the user who ran the installer,
	 * then remove their ~/.bk/accepted file, per lm.
	 */
	user = env{"USER"};
	home = env{"HOME"};
	if (user) {
		if (isreg("${home}/.bk/accepted")) {
			runit("/bin/rm -f '${home}/.bk/accepted'");
		} else if (isreg("/tmp/.bk/${user}/accepted")) {
			runit("/bin/rm -f '/tmp/.bk/${user}/accepted'");
		}
		runit("sudo -u '${user}' '${newbk}' lease flush -a");
	}

	/*
	 * Remove the accepted file for the elevated priv, so that the EULA
	 * is popped up every time by installtool.
	 */
	dotbk = `${newbk} dotbk`;
	runit("/bin/rm -f '${dotbk}/accepted'");

	/*
	 * The preinstall script looks for a pre-existing config file and
	 * copies it to $INSTALLER_TEMP. Look for that.
	 */
	tmp = getenv("INSTALLER_TEMP");
	if (isreg("${tmp}/config")) {
		runit("/bin/mv -f '${tmp}/config' "
		    "'${dstroot}/BitKeeper.app/Contents/Resources/bitkeeper'");
	}

	/*
	 * Run bk installtool to have it deal with the EULA and license keys.
	 * If installtool exits non-0, it means the user declined the EULA
	 * or quit the installation, so restore the old app bundle (if any)
	 * and bail.
	 */
	rc = system("'${newbk}' -?BK_DOTBK='${home}/.bk' installtool --installed",
		    undef, &out, &err);
	log("bk installtool: ${rc} '${out}' '${err}'");
	unless (rc == 0) {
		runit("/bin/rm -rf '${dstroot}/BitKeeper.app'");
		if (exists("${tmp}/oldbk.tar")) {
			runit("/usr/bin/tar -C '${dstroot}' -xf '${tmp}/oldbk.tar'");
		}
		exit(1);
	}

	/* Look for old versions of bk that we can uninstall. */
	paths = { "/usr/libexec/bitkeeper", "/usr/local/bitkeeper" };
	foreach (path in paths) {
		if (isdir(path)) rm_oldbk(path);
	}

	/*
	 * Create or update the bk symlink in /usr/bin if
	 * /usr/bin/bk does not exist, or
	 * /usr/bin/bk exists but doesn't point to our install dir.
	 */
	oldbk = runit("/usr/bin/readlink -n /usr/bin/bk");
	unless (oldbk == newbk) {
		create_bklink();
	}

	/* Make the user the app owner. */
	if (user) {
		runit("/usr/sbin/chown -R '${user}' '${dstroot}/BitKeeper.app'");
	}

	/* Call exit here, not return. */
	exit(0);
}

void
rm_oldbk(string path)
{
	string	ans, msg;

	unless (noprompt) {
		msg = "An old version of BitKeeper was found in\n${path}\n"
			"Would you like to remove it?";
		ans = tk_messageBox(default: "yes", icon: "info", type: "yesno",
				    title: "Old version of BitKeeper found",
				    message: msg);
		unless (ans == "yes") return;
	}
	unless (runit("/bin/rm -rf '${path}'") || noprompt) {
		msg = "Error ${rc} occurred: ${err}";
		tk_messageBox(default: "ok", icon: "error", type: "ok",
			      title: "Error", message: msg);
	}
}

string
runit(string cmd)
{
	string	out;

	/* Note that err is a global. */
	rc = system(cmd, undef, &out, &err);
	log("${cmd}: ${rc} '${out}' '${err}'");
	if (rc == 0) {
		return (out ? out : "");
	} else {
		return (undef);
	}
}

void
create_bklink(void)
{
	string	msg;

	/* Don't ask the user, just create the link if possible. */
	unless (runit("'${newbk}' links /usr/bin") || noprompt) {
		msg = "Unable to create symbolic link /usr/bin/bk. "
		      "You will need to add ${dirname(newbk)} to your PATH manually.";
		tk_messageBox(default: "ok", icon: "error", type: "ok",
			      title: "Error", message: msg);
	}
}

void
log(FMT fmt, ...args)
{
	string	d = Clock_format(Clock_seconds(), format: "%Y-%m-%d %H:%M:%S");

	unless (logf) logf = fopen("/tmp/bk-install-log.txt", "w");
	unless (logf) return;
	fprintf(logf, "${d}: ${fmt}\n", (expand)args);
}