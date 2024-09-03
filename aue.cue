package aue

import (
	"regexp"
	"strings"
	"tool/cli"
	"tool/exec"
	"tool/os"

	"github.com/abcue/tool"
)

#Command: tool.PrintRun & {
	#var: argocd?: {
		env: [string]: string
		server: string
		applications: [string]: argocd?: _
		remote:  string
		refspec: string
	}

	_local: env: os.Environ

	if #var.argocd != _|_ {
		// `eval $(cue cmd argocd-env)` to source
		"argocd-env": cli.Print & {
			text: strings.Join([for k, v in #var.argocd.env {"export \(k)=\(v)"}], "\n")
		}
		// log in to Argo CD
		"argocd-login": {
			runP: exec.Run & {cmd: "argocd login \(#var.argocd.server) --sso"}
		}
	}

	for name, app in #var.argocd.applications {
		if app.argocd != _|_ {
			let RUN = exec.Run & {env: #var.argocd.env & _local.env}

			// print argocd application details
			"argocd-app": _
			// print the specified argocd application details
			"argocd-app-\(name)": {
				runP: RUN & {cmd: #"cue export --expression application."\#(name)".argocd --out yaml"#}
			}
			// print manifests of an application
			"argocd-app-manifests": _
			// print manifests of the specified application
			"argocd-app-manifests-\(name)": {
				runP: RUN & {cmd: "argocd app manifests \(name)"}
			}
			// preview difference against the target and live state before syncing app and wait for user confirmation (shortcut)
			"argocd-app-preview": _
			// preview difference against the target and live state before syncing app and wait for user confirmation
			"argocd-app-preview-\(name)": {
				remote: RUN & {
					cmd:    "git remote --verbose"
					stdout: string
				}
				push: RUN & {
					let R = strings.Split([for ln in strings.Split(remote.stdout, "\n") if regexp.Match(#var.argocd.remote, ln) {ln}][0], "\t")[0]
					cmd: ["git", "push", R, #var.argocd.refspec]
					mustSucceed: false
				}
				rev: RUN & {
					cmd:    "git rev-parse HEAD"
					stdout: string
				}
				let APPNAME = name + app.alpha.app.suffix
				set: RUN & {
					$after: push
					cmd:    "argocd app set \(APPNAME) --revision \(rev.stdout)"
				}
				sync: RUN & {
					$after: set
					cmd:    "argocd app sync \(APPNAME) --preview-changes"
				}
				wait: RUN & {
					$after: sync
					cmd:    *"echo 'Sync success: \(sync.success)'" | _
					if sync.success {
						cmd: "argocd app wait \(APPNAME)"
					}
				}
				printR: _
			}
		}
	}
}
