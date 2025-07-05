defmodule Introspex.Postgres.IntrospectorTest do
  use ExUnit.Case, async: true

  alias Introspex.Postgres.Introspector

  describe "parse_default/1" do
    test "returns nil for nil input" do
      assert Introspector.parse_default(nil) == nil
    end

    test "returns nil for empty string" do
      assert Introspector.parse_default("") == nil
    end

    test "removes type casting from default values" do
      assert Introspector.parse_default("'default_value'::text") == "default_value"
      assert Introspector.parse_default("'123'::integer") == "123"
    end

    test "returns nil for sequence defaults" do
      assert Introspector.parse_default("nextval('users_id_seq'::regclass)") == nil
    end

    test "returns regular default values unchanged" do
      assert Introspector.parse_default("true") == "true"
      assert Introspector.parse_default("42") == "42"
    end
  end

  describe "decode_action/1" do
    test "decodes PostgreSQL foreign key actions" do
      assert Introspector.decode_action("a") == :no_action
      assert Introspector.decode_action("r") == :restrict
      assert Introspector.decode_action("c") == :cascade
      assert Introspector.decode_action("n") == :set_null
      assert Introspector.decode_action("d") == :set_default
    end

    test "returns :no_action for unknown actions" do
      assert Introspector.decode_action("x") == :no_action
      assert Introspector.decode_action("") == :no_action
      assert Introspector.decode_action(nil) == :no_action
    end
  end
end
