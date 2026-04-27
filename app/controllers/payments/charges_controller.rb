class Payments::ChargesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_charge

  def show
    send_data(
      @charge.receipt,
      disposition: :inline,
      filename: @charge.filename,
      type: "application/pdf"
    )
  end

  def invoice
    send_data(
      @charge.invoice,
      disposition: :inline,
      filename: @charge.invoice_filename,
      type: "application/pdf"
    )
  end

  private

  def set_charge
    @charge = current_workspace.pay_charges.find_by_prefix_id(params[:id])
  end
end
