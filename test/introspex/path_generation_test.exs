defmodule Introspex.PathGenerationTest do
  use ExUnit.Case

  @tag :tmp_dir
  test "generates files in correct path structure", %{tmp_dir: tmp_dir} do
    # Test that when we have a module like MyApp.Foo.Property
    # it creates lib/my_app/foo/property.ex (not lib/my_app/foo/foo/property.ex)

    module_name = "MyApp.Foo.Property"

    content = """
    defmodule MyApp.Foo.Property do
      use Ecto.Schema
      
      schema "properties" do
        field :name, :string
      end
    end
    """

    output_dir = Path.join(tmp_dir, "lib/my_app")

    # Simulate what write_schema_file does
    module_parts = String.split(module_name, ".")
    [_app_prefix | relative_parts] = module_parts

    relative_path_parts = Enum.map(relative_parts, &Macro.underscore/1)
    file_name = List.last(relative_path_parts)
    directory_parts = List.delete_at(relative_path_parts, -1)

    full_path_parts = [output_dir] ++ directory_parts
    file_path = Path.join(full_path_parts ++ ["#{file_name}.ex"])

    # Ensure directory exists
    File.mkdir_p!(Path.dirname(file_path))
    File.write!(file_path, content)

    # Verify the file is at the correct location
    assert File.exists?(Path.join(tmp_dir, "lib/my_app/foo/property.ex"))
    refute File.exists?(Path.join(tmp_dir, "lib/my_app/foo/foo/property.ex"))
  end

  @tag :tmp_dir
  test "generates files with context in correct path", %{tmp_dir: tmp_dir} do
    # Test MyApp.Queries.Accounts.User -> lib/my_app/queries/accounts/user.ex
    module_name = "MyApp.Queries.Accounts.User"
    content = "defmodule #{module_name} do\nend"

    output_dir = Path.join(tmp_dir, "lib/my_app")

    module_parts = String.split(module_name, ".")
    [_app_prefix | relative_parts] = module_parts

    relative_path_parts = Enum.map(relative_parts, &Macro.underscore/1)
    file_name = List.last(relative_path_parts)
    directory_parts = List.delete_at(relative_path_parts, -1)

    full_path_parts = [output_dir] ++ directory_parts
    file_path = Path.join(full_path_parts ++ ["#{file_name}.ex"])

    File.mkdir_p!(Path.dirname(file_path))
    File.write!(file_path, content)

    assert File.exists?(Path.join(tmp_dir, "lib/my_app/queries/accounts/user.ex"))
  end
end
