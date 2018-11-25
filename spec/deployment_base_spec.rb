RSpec.describe OpenStax::Aws::DeploymentBase do

  context "#subdomain_with_trailing_dot" do
    let(:instance) {
      described_class.new(env_name: env_name,
                          region: 'whatever',
                          name: 'a_name')
    }

    context "production env" do
      let(:env_name) { 'production' }

      context "blank site_name" do
        it 'is blank' do
          expect(instance.send(:subdomain_with_trailing_dot, site_name: "")).to be_blank
        end
      end

      context "non-blank site_name" do
        it 'is the site_name' do
          expect(instance.send(:subdomain_with_trailing_dot,site_name: "hi")).to eq "hi."
        end
      end
    end

    context "non-production env" do
      let(:env_name) { 'qa' }

      context "blank site_name" do
        it 'is the env name' do
          expect(instance.send(:subdomain_with_trailing_dot,site_name: "")).to eq "#{env_name}."
        end
      end

      context "non-blank site_name" do
        it 'is the site_name' do
          expect(instance.send(:subdomain_with_trailing_dot,site_name: "hi")).to eq "hi-#{env_name}."
        end
      end
    end
  end

end
