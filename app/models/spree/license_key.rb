module Spree
  class LicenseKey < ActiveRecord::Base
    belongs_to :inventory_unit, :class_name => "Spree::InventoryUnit"
    belongs_to :variant, :class_name => "Spree::Variant"
    belongs_to :license_key_type, :class_name => "Spree::LicenseKeyType"

    attr_accessible :license_key, :inventory_unit_id, :variant_id

    scope :available, where(inventory_unit_id: nil)
    scope :used, where('inventory_unit_id IS NOT NULL')

    # Max count of repeat to assign license key when could not assign.
    REPEAT_COUNT_LIMIT = 3

    def self.assign_license_keys!(inventory_unit, repeat_count=0)
      transaction do
        if inventory_unit.variant.license_key_types.empty?
          [self.get_available_key(inventory_unit)]
        else
          inventory_unit.variant.license_key_types.map do |key_type|
            self.get_available_key(inventory_unit, key_type)
          end
        end
      end
    rescue UnAssignLicenseKeys
      if repeat_count == REPEAT_COUNT_LIMIT
        raise LicenseKey::UnAssignLicenseKeys, "Order: #{inventory_unit.order.to_param}, Variant: #{inventory_unit.variant.to_param}"
      end
      # In order to avoid a collision, and repeat in a few seconds
      sleep(repeat_count+1)
      self.assign_license_keys!(inventory_unit, repeat_count+1)
    end

    class InsufficientLicenseKeys < ::StandardError; end
    class UnAssignLicenseKeys < ::StandardError; end

    private

    def self.get_available_key(inventory_unit, license_key_type = nil)
      license_key = self.where(:variant_id => inventory_unit.variant.id, :inventory_unit_id => nil, :license_key_type_id => license_key_type.try(:id)).first
      if license_key.nil?
        raise LicenseKey::InsufficientLicenseKeys, "Order: #{inventory_unit.order.to_param}, Variant: #{inventory_unit.variant.to_param}, License Key Type: #{license_key_type.try(:id)}"
      end
      updated_count = LicenseKey.where(id: license_key.id, inventory_unit_id: nil).update_all(inventory_unit_id: inventory_unit.id, updated_at: Time.now)
      raise UnAssignLicenseKeys if updated_count == 0
      license_key
    end
  end
end
