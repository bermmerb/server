/*
===========================================================================

  Copyright (c) 2025 LandSandBoat Dev Teams

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see http://www.gnu.org/licenses/

===========================================================================
*/

#include "0x04e_auc.h"

#include "common/utils.h"

#include "data/enums/zone_misc.h"
#include "entities/char_entity.h"
#include "packets/c2s/validation.h"
#include "utils/auctionutils.h"
#include "utils/jailutils.h"

namespace
{

// The menu only opens by talking to an auction counter within 6.0' (0x01a_action.cpp), and no packet tells the server
// when the client closes it. How far the client lets the character walk off with it open is not documented, so leave
// room for a few steps.
constexpr float MaxAuctionCounterDistance = 20.0f;

// Empty if the character is near the auction counter it opened the menu from.
auto auctionCounterError(const CCharEntity* PChar) -> std::string
{
    // !ah opens the menu anywhere, with no counter
    if (PChar->m_GMlevel > 0)
    {
        return {};
    }

    // Zoning, the Mog House included, reloads the character, which forgets the counter
    const auto* PCounter = PChar->auctionNpc_.resolve();
    if (PCounter == nullptr || PCounter->loc.zone != PChar->loc.zone)
    {
        return "Character has not opened the auction house at a counter in this zone.";
    }

    if (const float dist = distance(PChar->loc.p, PCounter->loc.p); dist > MaxAuctionCounterDistance)
    {
        return std::format("Character is {:.1f}y from auction counter {}.", dist, PCounter->getName());
    }

    return {};
}

} // namespace

auto GP_CLI_COMMAND_AUC::validate(MapSession* PSession, const CCharEntity* PChar) const -> PacketValidationResult
{
    const auto counterError = auctionCounterError(PChar);

    auto pv = PacketValidator(PChar)
                  .blockedBy({ BlockedState::InEvent })
                  .hasZoneMiscFlag(xi::ZoneMisc::AuctionHouse)
                  .mustEqual(counterError.empty(), true, counterError)
                  .mustEqual(jailutils::InPrison(PChar), false, "Character in jail")
                  .oneOf<GP_CLI_COMMAND_AUC_COMMAND>(this->Command)
                  .mustEqual(this->Result, 0, "Result not 0")
                  .mustEqual(this->ResultStatus, 0, "Result status");

    switch (this->Command)
    {
        case GP_CLI_COMMAND_AUC_COMMAND::AskCommit:
        {
            pv
                .range("Commission", this->Param.AskCommit.Commission, 1, 999999999)
                .range("ItemStacks", this->Param.AskCommit.ItemStacks, 0, 1);
        }
        break;
        case GP_CLI_COMMAND_AUC_COMMAND::Info:
        {
            // No specific parameter to validate for Info command
        }
        break;
        case GP_CLI_COMMAND_AUC_COMMAND::WorkCheck:
        {
            pv.mustEqual(this->AucWorkIndex, -1, "AucWorkIndex not -1");
        }
        break;
        case GP_CLI_COMMAND_AUC_COMMAND::LotIn:
        {
            pv
                .range("AucWorkIndex", this->AucWorkIndex, 0, 6)
                .range("LimitPrice", this->Param.LotIn.LimitPrice, 1, 999999999)
                .range("ItemStacks", this->Param.LotIn.ItemStacks, 0, 1);
        }
        break;
        case GP_CLI_COMMAND_AUC_COMMAND::Bid:
        {
            pv
                .range("AucWorkIndex", this->AucWorkIndex, 0, 6)
                .range("BidPrice", this->Param.Bid.BidPrice, 1, 999999999)
                .range("ItemStacks", this->Param.Bid.ItemStacks, 0, 1);
        }
        break;
        case GP_CLI_COMMAND_AUC_COMMAND::LotCancel:
        {
            pv.range("AucWorkIndex", this->AucWorkIndex, 0, 6);
        }
        break;
        case GP_CLI_COMMAND_AUC_COMMAND::LotCheck:
        {
            pv.range("AucWorkIndex", this->AucWorkIndex, 0, 6);
        }
        break;
        default:
            break;
    }

    return pv;
}

void GP_CLI_COMMAND_AUC::process(MapSession* PSession, CCharEntity* PChar) const
{
    const auto playerName = PChar->getName();

    switch (this->Command)
    {
        case GP_CLI_COMMAND_AUC_COMMAND::AskCommit:
        {
            auctionutils::SellingItems(PChar, this->Param.AskCommit);
        }
        break;
        case GP_CLI_COMMAND_AUC_COMMAND::Info:
        {
            auctionutils::OpenListOfSales(PChar);
            [[fallthrough]];
        }
        // FALLTHROUGH!
        case GP_CLI_COMMAND_AUC_COMMAND::WorkCheck:
        {
            auctionutils::RetrieveListOfItemsSoldByPlayer(PChar);
        }
        break;
        case GP_CLI_COMMAND_AUC_COMMAND::LotIn:
        {
            auctionutils::ProofOfPurchase(PChar, this->Param.LotIn);
        }
        break;
        case GP_CLI_COMMAND_AUC_COMMAND::Bid:
        {
            auctionutils::PurchasingItems(PChar, this->Param.Bid);
        }
        break;
        case GP_CLI_COMMAND_AUC_COMMAND::LotCancel:
        {
            auctionutils::CancelSale(PChar, this->AucWorkIndex);
        }
        break;
        case GP_CLI_COMMAND_AUC_COMMAND::LotCheck:
        {
            auctionutils::UpdateSaleListByPlayer(PChar, this->AucWorkIndex);
        }
        break;
        default:
            break;
    }
}
