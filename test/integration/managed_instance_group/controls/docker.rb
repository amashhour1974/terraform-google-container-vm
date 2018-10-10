# Copyright 2018 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

image = attribute('image', required: true, type: :string)
container_definition = attribute('container', required: true, type: :hash)
volume_definitions = attribute('volumes', required: true, type: :array)
restart_policy = attribute('restart_policy', required: true, type: :string)

control "docker" do
  title "Docker containers"

  describe docker.containers do
    its('images') { should include image }

    let!(:running_containers) { docker.containers.ids.map { |id| docker.object(id) } }
    let(:container) { running_containers.first { |d| d.Config.Image == image } }

    it "should have our container" do
      expect(container).not_to be_nil
    end

    it "should be running the designated image" do
      expect(container.State.Status).to eq "running"
    end

    it "should have a properly configured restart policy" do
      expect(container.HostConfig.RestartPolicy.Name).to eq restart_policy.downcase
    end

    let(:mounts) { container.Mounts ? container.Mounts : [] }
    let(:mount_definitions) { container_definition["volumeMounts"] }
    let(:persistent_volume_definitions) { volume_definitions.select { |v| v.keys.include?("gcePersistentDisk") } }
    let(:temporary_volume_definitions) { volume_definitions.select { |v| v.keys.include?("emptyDir") } }

    it "should have the right number of disk mounts" do
      expect(mounts.count).to eq mount_definitions.count
    end

    it "should have the right number of bound disk mounts" do
      expect(mounts.select { |m| m.Type == "bind" }.count).to eq mount_definitions.count
    end

    it "should have the right number of GCE persistent disks on the right mount points" do
      fs = mounts.select { |m| m.Source.match(/gce-persistent-disks/) }
      expect(fs.count).to eq persistent_volume_definitions.count
      persistent_volume_definitions.each_with_index do |vd, i|
        mount_definition = mount_definitions.select { |md| md["name"] == vd["name"] }.first
        expect(fs[i].Destination).to eq mount_definition["mountPath"]
        if mount_definition["readOnly"] == "false"
          expect(fs[i].RW).to eq true
        else
          expect(fs[i].RW).to eq false
        end
      end
    end

    it "should have the right number of tempfs disks on the right mount points" do
      fs = mounts.select { |m| m.Source.match(/tmpfss/) }
      expect(fs.count).to eq temporary_volume_definitions.count
      temporary_volume_definitions.each_with_index do |vd, i|
        mount_definition = mount_definitions.select { |md| md["name"] == vd["name"] }.first
        expect(fs[i].Destination).to eq mount_definition["mountPath"]
        if mount_definition["readOnly"] == "false"
          expect(fs[i].RW).to eq true
        else
          expect(fs[i].RW).to eq false
        end
      end
    end
  end
end