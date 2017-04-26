namespace :stretcher do
  set :exclude_dirs, fetch(:exclude_dirs) << "vendor/bundle" << "public/assets"
  set :assets_dependencies, %w(app/assets lib/assets vendor/assets Gemfile.lock config/routes.rb)

  def local_bundle_path
    @_local_bundle_path ||= fetch(:local_bundle_path, "vendor/bundle")
  end

  task :bundle do
    on application_builder_roles do
      within local_build_path do
        execute :bundle, :install, "--gemfile #{local_build_path}/Gemfile --deployment --path #{local_bundle_path} -j 4 --without development test"
      end
    end
  end

  task :asset_precompile do
    on application_builder_roles do
      within local_build_path do
        with rails_env: fetch(:rails_env) do
          begin
            latest_release = capture(:ls, '-xr', local_build_path).split[1]

            raise PrecompileRequired unless latest_release

            latest_release_path = local_build_path.join(latest_release)

            execute :ls, latest_release_path.join('assets_manifest_backup') rescue raise(PrecompileRequired)

            fetch(:assets_dependencies).each do |dep|
              release = release_path.join(dep)
              latest = latest_release_path.join(dep)
              next if [release, latest].map{|d| test "[ -e #{d} ]"}.uniq == [false]

              execute :diff, '-Nqr', release, latest rescue raise(PrecompileRequired)
            end

            info("Skipping asset precompile, no asset diff found")

            release_asset_path = local_build_path.join('public', fetch(:assets_prefix))
            begin
              execute :test, '-L', release_asset_path.to_s
            rescue
              execute :cp, '-r', latest_release_path.join('public', fetch(:assets_prefix)), release_asset_path.parent
            end

            execute :ls, release_asset_path.join('manifest*') rescue raise(PrecompileRequired)

          rescue PrecompileRequired
            execute :rm, '-rf', "public/assets"
            execute :bundle, :exec, :rake, 'assets:precompile'
          end
        end
      end
    end
  end
end

after 'stretcher:checkout_local', 'stretcher:bundle'
before 'stretcher:create_tarball', 'stretcher:asset_precompile'
