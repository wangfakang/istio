// Copyright 2019 Istio Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package kubectlcmd

import (
	"errors"
	"io/ioutil"
	"os/exec"
	"reflect"
	"testing"

	"k8s.io/utils/pointer"
)

// collector is a commandSite implementation that stubs cmd.Run() calls for tests
type collector struct {
	Error error
	Cmds  []*exec.Cmd
}

func (s *collector) Run(c *exec.Cmd) error {
	s.Cmds = append(s.Cmds, c)
	return s.Error
}

func TestKubectlApply(t *testing.T) {
	tests := []struct {
		name       string
		manifest   string
		kubeconfig string
		context    string
		namespace  string
		output     string
		prune      *bool
		dryrun     bool
		args       []string
		err        error
		expectArgs []string
	}{
		{
			name:       "manifest",
			namespace:  "",
			manifest:   "foo",
			expectArgs: []string{"kubectl", "apply", "-f", "-"},
		},
		{
			name:       "manifest with namespace",
			namespace:  "kube-system",
			manifest:   "heynow",
			expectArgs: []string{"kubectl", "apply", "-n", "kube-system", "-f", "-"},
		},
		{
			name:       "manifest with context",
			context:    "ctx",
			manifest:   "heynow",
			expectArgs: []string{"kubectl", "apply", "--context", "ctx", "-f", "-"},
		},
		{
			name:       "manifest with kubeconfig",
			kubeconfig: "~/.kube/config",
			manifest:   "heynow",
			expectArgs: []string{"kubectl", "apply", "--kubeconfig", "~/.kube/config", "-f", "-"},
		},
		{
			name:       "manifest with output",
			output:     "out",
			manifest:   "heynow",
			expectArgs: []string{"kubectl", "apply", "-o", "out", "-f", "-"},
		},
		{
			name:       "manifest with prune",
			prune:      pointer.BoolPtr(true),
			manifest:   "heynow",
			expectArgs: []string{"kubectl", "apply", "--prune", "-f", "-"},
		},
		{
			name:       "manifest with verbose",
			context:    "ctx",
			manifest:   "heynow",
			expectArgs: []string{"kubectl", "apply", "--context", "ctx", "-f", "-"},
		},
		{
			name:       "manifest with prune args",
			namespace:  "kube-system",
			manifest:   "heynow",
			args:       []string{"--prune=true", "--prune-whitelist=hello-world"},
			expectArgs: []string{"kubectl", "apply", "-n", "kube-system", "--prune=true", "--prune-whitelist=hello-world", "-f", "-"},
		},
		{
			name:       "dry run",
			dryrun:     true,
			manifest:   "heynow",
			expectArgs: nil,
		},
		{
			name:       "empty manifest",
			manifest:   "",
			expectArgs: nil,
		},
		{
			name:       "command err",
			manifest:   "heynow",
			expectArgs: []string{"kubectl", "apply", "-f", "-"},
			err:        errors.New("an error"),
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			cs := collector{Error: test.err}
			kubectl := &Client{cmdSite: &cs}
			opts := &Options{
				Kubeconfig: test.kubeconfig,
				Context:    test.context,
				Namespace:  test.namespace,
				Output:     test.output,
				Prune:      test.prune,
				ExtraArgs:  test.args,
				DryRun:     test.dryrun,
				Verbose:    true,
			}
			_, _, err := kubectl.Apply(test.manifest, opts)

			if test.err != nil && err == nil {
				t.Error("expected error to occur")
			} else if test.err == nil && err != nil {
				t.Errorf("unexpected error: %v", err)
			}

			if test.expectArgs == nil {
				if len(cs.Cmds) != 0 {
					t.Errorf("expected 0 commands to be invoked, got: %d", len(cs.Cmds))
				}
				return
			} else if len(cs.Cmds) != 1 {
				t.Errorf("expected 1 command to be invoked, got: %d", len(cs.Cmds))
			}

			cmd := cs.Cmds[0]
			if !reflect.DeepEqual(cmd.Args, test.expectArgs) {
				t.Errorf("argument mistmatch, expected: %v, got: %v", test.expectArgs, cmd.Args)
			}

			stdinBytes, err := ioutil.ReadAll(cmd.Stdin)
			if err != nil {
				t.Fatal(err)
			}
			if stdin := string(stdinBytes); stdin != test.manifest {
				t.Errorf("manifest mismatch, expected: %v, got: %v", test.manifest, stdin)
			}
		})
	}

}

func TestKubectlDelete(t *testing.T) {
	tests := []struct {
		name       string
		namespace  string
		manifest   string
		args       []string
		err        error
		expectArgs []string
	}{
		{
			name:       "manifest",
			namespace:  "",
			manifest:   "foo",
			expectArgs: []string{"kubectl", "delete", "-f", "-"},
		},
		{
			name:       "manifest with delete",
			namespace:  "kube-system",
			manifest:   "heynow",
			expectArgs: []string{"kubectl", "delete", "-n", "kube-system", "-f", "-"},
		},
		{
			name:       "empty manifest",
			namespace:  "",
			manifest:   "",
			expectArgs: nil,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			cs := collector{Error: test.err}
			kubectl := &Client{cmdSite: &cs}
			opts := &Options{
				Namespace: test.namespace,
				ExtraArgs: test.args,
			}
			_, _, err := kubectl.Delete(test.manifest, opts)

			if test.err != nil && err == nil {
				t.Error("expected error to occur")
			} else if test.err == nil && err != nil {
				t.Errorf("unexpected error: %v", err)
			}

			if test.expectArgs == nil {
				if len(cs.Cmds) != 0 {
					t.Errorf("expected 0 commands to be invoked, got: %d", len(cs.Cmds))
				}
				return
			} else if len(cs.Cmds) != 1 {
				t.Errorf("expected 1 command to be invoked, got: %d", len(cs.Cmds))
			}

			cmd := cs.Cmds[0]
			if !reflect.DeepEqual(cmd.Args, test.expectArgs) {
				t.Errorf("argument mistmatch, expected: %v, got: %v", test.expectArgs, cmd.Args)
			}

			stdinBytes, err := ioutil.ReadAll(cmd.Stdin)
			if err != nil {
				t.Fatal(err)
			}
			if stdin := string(stdinBytes); stdin != test.manifest {
				t.Errorf("manifest mismatch, expected: %v, got: %v", test.manifest, stdin)
			}
		})
	}
}

func TestKubectlGetAll(t *testing.T) {
	tests := []struct {
		name       string
		namespace  string
		args       []string
		err        error
		expectArgs []string
	}{
		{
			name:       "default",
			namespace:  "",
			expectArgs: []string{"kubectl", "get", "all"},
		},
		{
			name:       "namespace",
			namespace:  "kube-system",
			expectArgs: []string{"kubectl", "get", "all", "-n", "kube-system"},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			cs := collector{Error: test.err}
			kubectl := &Client{cmdSite: &cs}
			opts := &Options{
				Namespace: test.namespace,
				ExtraArgs: test.args,
			}
			_, _, err := kubectl.GetAll(opts)

			if test.err != nil && err == nil {
				t.Error("expected error to occur")
			} else if test.err == nil && err != nil {
				t.Errorf("unexpected error: %v", err)
			}

			if len(cs.Cmds) != 1 {
				t.Errorf("expected 1 command to be invoked, got: %d", len(cs.Cmds))
			}

			cmd := cs.Cmds[0]
			if !reflect.DeepEqual(cmd.Args, test.expectArgs) {
				t.Errorf("argument mistmatch, expected: %v, got: %v", test.expectArgs, cmd.Args)
			}
		})
	}
}

func TestKubectlGetConfig(t *testing.T) {
	tests := []struct {
		name       string
		cmname     string
		namespace  string
		args       []string
		err        error
		expectArgs []string
	}{
		{
			name:       "default",
			cmname:     "foo",
			namespace:  "",
			expectArgs: []string{"kubectl", "get", "cm", "foo"},
		},
		{
			name:       "namespace",
			cmname:     "foo",
			namespace:  "kube-system",
			expectArgs: []string{"kubectl", "get", "cm", "foo", "-n", "kube-system"},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			cs := collector{Error: test.err}
			kubectl := &Client{cmdSite: &cs}
			opts := &Options{
				Namespace: test.namespace,
				ExtraArgs: test.args,
			}
			_, _, err := kubectl.GetConfigMap(test.cmname, opts)

			if test.err != nil && err == nil {
				t.Error("expected error to occur")
			} else if test.err == nil && err != nil {
				t.Errorf("unexpected error: %v", err)
			}

			if len(cs.Cmds) != 1 {
				t.Errorf("expected 1 command to be invoked, got: %d", len(cs.Cmds))
			}

			cmd := cs.Cmds[0]
			if !reflect.DeepEqual(cmd.Args, test.expectArgs) {
				t.Errorf("argument mistmatch, expected: %v, got: %v", test.expectArgs, cmd.Args)
			}
		})
	}
}
