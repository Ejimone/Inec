// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract RealEstateRental {
    // Enum to track apartment state
    enum State { Available, Reserved, Rented }

    // Struct to store apartment details
    struct Apartment {
        uint id;              // Unique identifier
        string physicalAddress;       // Physical address
        string description;   // Apartment details
        uint monthlyRent;     // Rent per month in wei
        uint deposit;         // Security deposit in wei
        uint leaseDuration;   // Lease length in months
        address landlord;     // Landlord's Ethereum address
        address agent;        // Agent's Ethereum address (optional)
        uint agentCommission; // Commission in wei (optional)
        address tenant;       // Tenant's Ethereum address
        uint startTime;       // Lease start timestamp
        uint monthsPaid;      // Number of months paid
        State state;          // Current state
        address reservedBy;   // Address of tenant who reserved
        uint reservationTime; // Reservation timestamp
    }

    // Mapping from apartment ID to Apartment struct
    mapping(uint => Apartment) public apartments;

    // Counter for generating unique apartment IDs
    uint public nextApartmentId = 1;

    // Constant for approximate month duration (30 days in seconds)
    uint constant MONTH = 30 days;

    // Events for tracking state changes
    event ApartmentListed(uint id, address landlord);
    event ApartmentReserved(uint id, address tenant);
    event ReservationAccepted(uint id, address tenant);
    event ReservationRejected(uint id, address tenant);
    event ReservationWithdrawn(uint id, address tenant);
    event RentPaid(uint id, uint month);
    event LeaseTerminated(uint id);
    event DepositReclaimed(uint id);

    /**
     * @dev Landlord lists a new apartment
     * @param _address Physical address
     * @param _description Apartment details
     * @param _monthlyRent Monthly rent in wei
     * @param _deposit Deposit amount in wei
     * @param _leaseDuration Duration in months
     * @param _agent Agent's address (address(0) if none)
     * @param _agentCommission Commission in wei (0 if no agent)
     */
    function listApartment(
        string memory _address,
        string memory _description,
        uint _monthlyRent,
        uint _deposit,
        uint _leaseDuration,
        address _agent,
        uint _agentCommission
    ) public {
        require(_leaseDuration > 0, "Lease duration must be positive");
        require(_agentCommission <= _monthlyRent, "Commission too high");

        apartments[nextApartmentId] = Apartment({
            id: nextApartmentId,
            physicalAddress: _address,
            description: _description,
            monthlyRent: _monthlyRent,
            deposit: _deposit,
            leaseDuration: _leaseDuration,
            landlord: msg.sender,
            agent: _agent,
            agentCommission: _agentCommission,
            tenant: address(0),
            startTime: 0,
            monthsPaid: 0,
            state: State.Available,
            reservedBy: address(0),
            reservationTime: 0
        });

        emit ApartmentListed(nextApartmentId, msg.sender);
        nextApartmentId++;
    }

    /**
     * @dev Tenant reserves an apartment by sending deposit + first month's rent
     * @param _apartmentId ID of the apartment
     */
    function reserveApartment(uint _apartmentId) public payable {
        Apartment storage apt = apartments[_apartmentId];
        require(apt.state == State.Available, "Apartment not available");
        require(msg.value == apt.deposit + apt.monthlyRent, "Incorrect payment amount");

        apt.state = State.Reserved;
        apt.reservedBy = msg.sender;
        apt.reservationTime = block.timestamp;

        emit ApartmentReserved(_apartmentId, msg.sender);
    }

    /**
     * @dev Landlord accepts a reservation, starting the lease
     * @param _apartmentId ID of the apartment
     */
    function acceptReservation(uint _apartmentId) public {
        Apartment storage apt = apartments[_apartmentId];
        require(msg.sender == apt.landlord, "Only landlord can accept");
        require(apt.state == State.Reserved, "Not reserved");

        apt.state = State.Rented;
        apt.tenant = apt.reservedBy;
        apt.startTime = block.timestamp;
        apt.monthsPaid = 1;

        // Transfer agent commission if applicable
        if (apt.agent != address(0)) {
            payable(apt.agent).transfer(apt.agentCommission);
        }
        // Transfer remaining first month's rent to landlord
        payable(apt.landlord).transfer(apt.monthlyRent - apt.agentCommission);

        emit ReservationAccepted(_apartmentId, apt.tenant);
    }

    /**
     * @dev Landlord rejects a reservation, refunding the tenant
     * @param _apartmentId ID of the apartment
     */
    function rejectReservation(uint _apartmentId) public {
        Apartment storage apt = apartments[_apartmentId];
        require(msg.sender == apt.landlord, "Only landlord can reject");
        require(apt.state == State.Reserved, "Not reserved");

        address reserver = apt.reservedBy;
        apt.state = State.Available;
        apt.reservedBy = address(0);
        apt.reservationTime = 0;

        payable(reserver).transfer(apt.deposit + apt.monthlyRent);
        emit ReservationRejected(_apartmentId, reserver);
    }

    /**
     * @dev Tenant withdraws their reservation before acceptance
     * @param _apartmentId ID of the apartment
     */
    function withdrawReservation(uint _apartmentId) public {
        Apartment storage apt = apartments[_apartmentId];
        require(apt.state == State.Reserved, "Not reserved");
        require(msg.sender == apt.reservedBy, "Only reserver can withdraw");

        apt.state = State.Available;
        apt.reservedBy = address(0);
        apt.reservationTime = 0;

        payable(msg.sender).transfer(apt.deposit + apt.monthlyRent);
        emit ReservationWithdrawn(_apartmentId, msg.sender);
    }

    /**
     * @dev Tenant pays monthly rent
     * @param _apartmentId ID of the apartment
     */
    function payRent(uint _apartmentId) public payable {
        Apartment storage apt = apartments[_apartmentId];
        require(apt.state == State.Rented, "Not rented");
        require(msg.sender == apt.tenant, "Only tenant can pay rent");
        require(msg.value == apt.monthlyRent, "Incorrect rent amount");
        require(apt.monthsPaid < apt.leaseDuration, "Lease already fully paid");

        apt.monthsPaid += 1;
        payable(apt.landlord).transfer(apt.monthlyRent);

        emit RentPaid(_apartmentId, apt.monthsPaid);
    }

    /**
     * @dev Landlord terminates lease if rent is overdue
     * @param _apartmentId ID of the apartment
     */
    function terminateLease(uint _apartmentId) public {
        Apartment storage apt = apartments[_apartmentId];
        require(apt.state == State.Rented, "Not rented");
        require(msg.sender == apt.landlord, "Only landlord can terminate");

        uint paidUntil = apt.startTime + apt.monthsPaid * MONTH;
        require(block.timestamp > paidUntil, "Cannot terminate yet");

        apt.state = State.Available;
        apt.tenant = address(0);
        apt.startTime = 0;
        apt.monthsPaid = 0;

        payable(apt.landlord).transfer(apt.deposit);
        emit LeaseTerminated(_apartmentId);
    }

    /**
     * @dev Tenant reclaims deposit after lease ends and all rents are paid
     * @param _apartmentId ID of the apartment
     */
    function reclaimDeposit(uint _apartmentId) public {
        Apartment storage apt = apartments[_apartmentId];
        require(apt.state == State.Rented, "Not rented");
        require(msg.sender == apt.tenant, "Only tenant can reclaim");

        uint leaseEnd = apt.startTime + apt.leaseDuration * MONTH;
        require(block.timestamp >= leaseEnd, "Lease not ended");
        require(apt.monthsPaid >= apt.leaseDuration, "Not all rents paid");

        address tenant = apt.tenant;
        apt.state = State.Available;
        apt.tenant = address(0);
        apt.startTime = 0;
        apt.monthsPaid = 0;

        payable(tenant).transfer(apt.deposit);
        emit DepositReclaimed(_apartmentId);
    }

    /**
     * @dev View function to get apartment details
     * @param _id Apartment ID
     * @return Apartment struct
     */
    function getApartment(uint _id) public view returns (Apartment memory) {
        return apartments[_id];
    }
}